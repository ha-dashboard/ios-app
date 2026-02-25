#!/usr/bin/env node
/**
 * Captures screenshots of each view in the HA test-harness dashboard.
 * Produces one PNG per view + individual section crops for granular comparison.
 *
 * Usage: node scripts/capture-screenshots.mjs [--url https://demo.ha-dash.app]
 */
import { chromium } from 'playwright';
import { mkdir } from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const HA_URL = process.argv.includes('--url')
  ? process.argv[process.argv.indexOf('--url') + 1]
  : 'https://demo.ha-dash.app';

// --theme dark|light|both (default: both)
const THEME_ARG = process.argv.includes('--theme')
  ? process.argv[process.argv.indexOf('--theme') + 1]
  : 'both';
const THEMES = THEME_ARG === 'both' ? ['dark', 'light'] : [THEME_ARG];

// Dashboard views to capture — must match test-harness.yaml view paths
const VIEWS = [
  { path: 'lighting',  title: 'Lighting & Controls' },
  { path: 'climate',   title: 'Climate & Weather' },
  { path: 'sensors',   title: 'Sensors' },
  { path: 'security',  title: 'Security' },
  { path: 'media',     title: 'Media' },
  { path: 'vacuums',   title: 'Vacuums' },
  { path: 'inputs',    title: 'Inputs' },
  { path: 'entities',  title: 'Entities Cards' },
];

async function waitForHAReady(page) {
  // Wait for the HA frontend to fully load
  await page.waitForLoadState('networkidle', { timeout: 30000 });
  // Wait for the main panel to appear
  await page.waitForTimeout(2000);
}

async function authenticate(page) {
  // Authenticate via the HA REST API and inject tokens into localStorage.
  // This bypasses the login UI entirely.
  console.log('  Authenticating via HA REST API...');

  const clientId = `${HA_URL}/`;

  // Step 1: Start a login flow
  const flowResp = await fetch(`${HA_URL}/auth/login_flow`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_id: clientId, handler: ['homeassistant', null], redirect_uri: clientId }),
  });
  const flow = await flowResp.json();

  // Step 2: Submit credentials
  const loginResp = await fetch(`${HA_URL}/auth/login_flow/${flow.flow_id}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_id: clientId, username: 'test', password: 'testtest' }),
  });
  const login = await loginResp.json();
  if (!login.result) {
    throw new Error(`Login failed: ${JSON.stringify(login)}`);
  }

  // Step 3: Exchange auth code for tokens
  const tokenResp = await fetch(`${HA_URL}/auth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=authorization_code&code=${login.result}&client_id=${encodeURIComponent(clientId)}`,
  });
  const tokens = await tokenResp.json();
  if (!tokens.access_token) {
    throw new Error(`Token exchange failed: ${JSON.stringify(tokens)}`);
  }
  console.log('  Got access token');

  // Step 4: Navigate to HA origin so we can set localStorage on the right domain
  await page.goto(HA_URL, { waitUntil: 'domcontentloaded', timeout: 15000 });

  // Step 5: Inject tokens into localStorage (same format HA frontend uses)
  await page.evaluate((tokenData) => {
    const hassTokens = {
      hassUrl: tokenData.hassUrl,
      clientId: tokenData.clientId,
      refresh_token: tokenData.refresh_token,
      access_token: tokenData.access_token,
      token_type: 'Bearer',
      expires_in: tokenData.expires_in,
      // Set expiry far in the future so the token stays valid during capture
      expires: Date.now() + tokenData.expires_in * 1000,
    };
    localStorage.setItem('hassTokens', JSON.stringify(hassTokens));
  }, {
    hassUrl: HA_URL,
    clientId,
    refresh_token: tokens.refresh_token,
    access_token: tokens.access_token,
    expires_in: tokens.expires_in || 1800,
  });

  console.log('  Injected tokens into localStorage');

  // Step 6: Reload to pick up the auth session
  await page.goto(HA_URL, { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(3000);
  console.log(`  Authenticated — landed on: ${page.url()}`);
}

async function captureView(page, view, outputDir) {
  const url = `${HA_URL}/test-harness/${view.path}`;
  console.log(`  Capturing: ${view.title} (${url})`);

  await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(3000); // Let cards render fully

  // Full-page screenshot of the view
  const viewFile = path.join(outputDir, `view-${view.path}.png`);
  await page.screenshot({ path: viewFile, fullPage: true });
  console.log(`    Saved: view-${view.path}.png`);

  // Capture individual sections by piercing the HA 2026.2 shadow DOM.
  // Path: home-assistant > home-assistant-main > ha-drawer > (slot) >
  //   partial-panel-resolver > ha-panel-lovelace > hui-root >
  //   hui-view-container#view > hui-view > hui-sections-view > hui-section[]
  const sectionData = await page.evaluate(() => {
    try {
      const ha = document.querySelector('home-assistant');
      const main = ha?.shadowRoot?.querySelector('home-assistant-main');
      const drawer = main?.shadowRoot?.querySelector('ha-drawer');
      const contentSlot = drawer?.shadowRoot?.querySelector('.mdc-drawer-app-content slot');
      const assigned = contentSlot?.assignedElements?.() || [];
      const resolver = assigned.find(e => e.tagName?.toLowerCase() === 'partial-panel-resolver');
      const panel = resolver?.querySelector('ha-panel-lovelace');
      const huiRoot = panel?.shadowRoot?.querySelector('hui-root');
      // In HA 2026.2, #view is a hui-view-container with hui-view inside
      const viewContainer = huiRoot?.shadowRoot?.querySelector('#view') ||
                            huiRoot?.shadowRoot?.querySelector('hui-view-container');
      const huiView = viewContainer?.querySelector('hui-view');
      // hui-view may have a shadow root or contain hui-sections-view directly
      const sectionsView = huiView?.shadowRoot?.querySelector('hui-sections-view') ||
                           huiView?.querySelector('hui-sections-view');
      if (!sectionsView?.shadowRoot) return [];
      const sections = sectionsView.shadowRoot.querySelectorAll('hui-section');
      return [...sections].map((sec, i) => {
        const rect = sec.getBoundingClientRect();
        // Get section title from hui-grid-section > heading if available
        const gridSection = sec.shadowRoot?.querySelector('hui-grid-section');
        const heading = gridSection?.shadowRoot?.querySelector('.heading')?.textContent?.trim() ||
                        gridSection?.shadowRoot?.querySelector('h2')?.textContent?.trim() || '';
        return { index: i, x: rect.x, y: rect.y, width: rect.width, height: rect.height, title: heading };
      });
    } catch (e) {
      return [];
    }
  });

  if (sectionData.length > 0) {
    console.log(`    Found ${sectionData.length} sections`);
    for (const sec of sectionData) {
      if (sec.width > 0 && sec.height > 0) {
        const label = sec.title ? ` (${sec.title})` : '';
        const sectionFile = path.join(outputDir, `section-${view.path}-${sec.index}.png`);
        await page.screenshot({ path: sectionFile, clip: { x: sec.x, y: sec.y, width: sec.width, height: sec.height } });
        console.log(`    Saved: section-${view.path}-${sec.index}.png${label}`);
      }
    }
  }
}

async function setHATheme(page, theme) {
  // Set HA's own frontend theme via the WebSocket API.
  // HA respects the browser's prefers-color-scheme for its default theme,
  // but we also call the set_theme service to be explicit.
  await page.evaluate(async (themeName) => {
    // Access the hass object from the HA frontend
    const ha = document.querySelector('home-assistant');
    if (!ha?.hass?.callService) return;
    try {
      await ha.hass.callService('frontend', 'set_theme', {
        name: themeName === 'dark' ? 'default' : 'default',
        mode: themeName,
      });
    } catch (e) {
      // set_theme may not be available, browser colorScheme handles it
    }
  }, theme);
  await page.waitForTimeout(1000);
}

async function main() {
  console.log('HA Test Harness Screenshot Capture');
  console.log(`Target: ${HA_URL}`);
  console.log(`Themes: ${THEMES.join(', ')}`);
  console.log('');

  const browser = await chromium.launch({ headless: true });

  for (const theme of THEMES) {
    const outputDir = path.join(__dirname, '..', 'screenshots', 'ha-web', theme);
    await mkdir(outputDir, { recursive: true });

    console.log(`\n--- Theme: ${theme} ---`);

    const context = await browser.newContext({
      viewport: { width: 1280, height: 800 },
      deviceScaleFactor: 2,
      colorScheme: theme,
    });
    const page = await context.newPage();

    try {
      console.log('Connecting to Home Assistant...');
      await page.goto(HA_URL, { waitUntil: 'networkidle', timeout: 30000 });
      await authenticate(page);
      await waitForHAReady(page);
      await setHATheme(page, theme);
      console.log('Connected.\n');

      for (const view of VIEWS) {
        await captureView(page, view, outputDir);
      }

      console.log(`\nTheme '${theme}' complete. Saved to: ${outputDir}`);
    } catch (err) {
      console.error(`Error (${theme}): ${err.message}`);
      const debugFile = path.join(outputDir, 'debug-error.png');
      await page.screenshot({ path: debugFile, fullPage: true });
      console.error(`Debug screenshot saved to: ${debugFile}`);
    } finally {
      await context.close();
    }
  }

  await browser.close();
  console.log('\nDone.');
}

main();
