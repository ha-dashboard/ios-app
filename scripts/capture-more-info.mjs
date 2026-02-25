#!/usr/bin/env node
/**
 * Captures HA web more-info dialog screenshots for each entity domain.
 * Uses REST API auth + localStorage injection (same approach as capture-screenshots.mjs).
 *
 * Usage: node scripts/capture-more-info.mjs [--url https://demo.ha-dash.app]
 */
import { chromium } from 'playwright';
import { mkdirSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HA_URL = process.argv.includes('--url')
  ? process.argv[process.argv.indexOf('--url') + 1]
  : 'https://demo.ha-dash.app';

const PROJECT_ROOT = path.join(__dirname, '..');
const OUTPUT_DIR = path.join(PROJECT_ROOT, 'screenshots', 'more-info');
mkdirSync(OUTPUT_DIR, { recursive: true });

// Representative entities per domain — covers all domains with more-info dialogs
const ENTITIES = [
  { id: 'light.ceiling_lights', domain: 'light', name: 'ceiling-lights-on' },
  { id: 'light.bed_light', domain: 'light', name: 'bed-light-off' },
  { id: 'climate.hvac', domain: 'climate', name: 'hvac-heat' },
  { id: 'climate.ecobee', domain: 'climate', name: 'ecobee-off' },
  { id: 'sensor.outside_temperature', domain: 'sensor', name: 'temperature' },
  { id: 'sensor.outside_humidity', domain: 'sensor', name: 'humidity' },
  { id: 'binary_sensor.movement_backyard', domain: 'binary_sensor', name: 'motion' },
  { id: 'switch.decorative_lights', domain: 'switch', name: 'decorative-on' },
  { id: 'switch.ac', domain: 'switch', name: 'ac-off' },
  { id: 'cover.kitchen_window', domain: 'cover', name: 'kitchen-window' },
  { id: 'cover.hall_window', domain: 'cover', name: 'hall-window' },
  { id: 'fan.living_room_fan', domain: 'fan', name: 'living-room-fan' },
  { id: 'fan.ceiling_fan', domain: 'fan', name: 'ceiling-fan-on' },
  { id: 'lock.front_door', domain: 'lock', name: 'front-door-locked' },
  { id: 'lock.kitchen_door', domain: 'lock', name: 'kitchen-unlocked' },
  { id: 'media_player.living_room', domain: 'media_player', name: 'living-room-playing' },
  { id: 'media_player.bedroom', domain: 'media_player', name: 'bedroom-playing' },
  { id: 'vacuum.demo_vacuum_0_ground_floor', domain: 'vacuum', name: 'vacuum-docked' },
  { id: 'alarm_control_panel.security', domain: 'alarm', name: 'security-disarmed' },
  { id: 'humidifier.hygrostat', domain: 'humidifier', name: 'hygrostat-on' },
  { id: 'input_boolean.in_meeting', domain: 'input_boolean', name: 'in-meeting' },
  { id: 'input_number.target_temperature', domain: 'input_number', name: 'target-temp' },
  { id: 'input_select.media_source', domain: 'input_select', name: 'media-source' },
  { id: 'timer.laundry', domain: 'timer', name: 'laundry-idle' },
  { id: 'counter.page_views', domain: 'counter', name: 'page-views' },
  { id: 'scene.movie_night', domain: 'scene', name: 'movie-night' },
  { id: 'weather.demo_weather_south', domain: 'weather', name: 'weather-sunny' },
  { id: 'person.test', domain: 'person', name: 'person-test' },
  { id: 'update.demo_add_on', domain: 'update', name: 'demo-addon' },
  { id: 'siren.siren', domain: 'siren', name: 'siren-on' },
  { id: 'valve.front_garden', domain: 'valve', name: 'front-garden' },
  { id: 'water_heater.demo_water_heater', domain: 'water_heater', name: 'water-heater' },
  { id: 'number.volume', domain: 'number', name: 'volume' },
  { id: 'select.speed', domain: 'select', name: 'speed' },
  { id: 'date.date', domain: 'date', name: 'date' },
  { id: 'text.text', domain: 'text', name: 'text' },
  { id: 'button.push', domain: 'button', name: 'push' },
  { id: 'camera.demo_camera', domain: 'camera', name: 'demo-camera' },
];

async function authenticate(page) {
  // REST API auth flow — same as capture-screenshots.mjs
  console.log('  Authenticating via HA REST API...');
  const clientId = `${HA_URL}/`;

  const flowResp = await fetch(`${HA_URL}/auth/login_flow`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_id: clientId, handler: ['homeassistant', null], redirect_uri: clientId }),
  });
  const flow = await flowResp.json();

  const loginResp = await fetch(`${HA_URL}/auth/login_flow/${flow.flow_id}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_id: clientId, username: 'test', password: 'testtest' }),
  });
  const login = await loginResp.json();
  if (!login.result) throw new Error(`Login failed: ${JSON.stringify(login)}`);

  const tokenResp = await fetch(`${HA_URL}/auth/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=authorization_code&code=${login.result}&client_id=${encodeURIComponent(clientId)}`,
  });
  const tokens = await tokenResp.json();
  if (!tokens.access_token) throw new Error(`Token exchange failed: ${JSON.stringify(tokens)}`);
  console.log('  Got access token');

  // Navigate to HA origin so we can set localStorage
  await page.goto(HA_URL, { waitUntil: 'domcontentloaded', timeout: 15000 });

  // Inject tokens into localStorage
  await page.evaluate((tokenData) => {
    localStorage.setItem('hassTokens', JSON.stringify({
      hassUrl: tokenData.hassUrl,
      clientId: tokenData.clientId,
      refresh_token: tokenData.refresh_token,
      access_token: tokenData.access_token,
      token_type: 'Bearer',
      expires_in: tokenData.expires_in,
      expires: Date.now() + tokenData.expires_in * 1000,
    }));
  }, {
    hassUrl: HA_URL,
    clientId,
    refresh_token: tokens.refresh_token,
    access_token: tokens.access_token,
    expires_in: tokens.expires_in || 1800,
  });
  console.log('  Injected tokens into localStorage');

  // Reload to pick up auth session
  await page.goto(HA_URL, { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(3000);
  console.log(`  Authenticated — landed on: ${page.url()}`);
}

async function main() {
  console.log('HA More-Info Dialog Screenshot Capture');
  console.log(`Target: ${HA_URL}`);
  console.log('');

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    deviceScaleFactor: 2,
    colorScheme: 'light',
  });
  const page = await context.newPage();

  // Authenticate
  await page.goto(HA_URL, { waitUntil: 'networkidle', timeout: 30000 });
  await authenticate(page);

  // Set light theme explicitly
  await page.evaluate(async () => {
    const ha = document.querySelector('home-assistant');
    if (ha?.hass?.callService) {
      try {
        await ha.hass.callService('frontend', 'set_theme', { name: 'default', mode: 'light' });
      } catch (e) { /* ignore */ }
    }
  });
  await page.waitForTimeout(1000);

  // Navigate to the test-harness dashboard so we have entities loaded
  await page.goto(`${HA_URL}/test-harness/lighting`, { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(3000);

  let captured = 0;
  let failed = 0;

  for (const entity of ENTITIES) {
    const filename = `${entity.domain}--${entity.name}.png`;
    const filepath = path.join(OUTPUT_DIR, filename);
    console.log(`  ${entity.id} -> ${filename}`);

    try {
      // Fire hass-more-info event to open the dialog
      await page.evaluate((entityId) => {
        const event = new CustomEvent('hass-more-info', {
          detail: { entityId },
          bubbles: true,
          composed: true,
        });
        document.querySelector('home-assistant')?.dispatchEvent(event);
      }, entity.id);

      // Wait for dialog to render (history chart takes a moment)
      await page.waitForTimeout(3000);

      // Try to find and screenshot just the dialog surface
      const dialogBox = await page.evaluate(() => {
        const ha = document.querySelector('home-assistant');
        if (!ha?.shadowRoot) return null;

        // HA 2026.x: ha-more-info-dialog > ha-dialog > .mdc-dialog__surface
        const moreInfo = ha.shadowRoot.querySelector('ha-more-info-dialog');
        if (!moreInfo?.shadowRoot) return null;

        const haDialog = moreInfo.shadowRoot.querySelector('ha-dialog');
        if (!haDialog?.shadowRoot) return null;

        const surface = haDialog.shadowRoot.querySelector('.mdc-dialog__surface');
        if (!surface) return null;

        const r = surface.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) return null;
        return { x: r.x, y: r.y, width: r.width, height: r.height };
      });

      if (dialogBox && dialogBox.width > 50 && dialogBox.height > 50) {
        // Clip to dialog surface only
        await page.screenshot({
          path: filepath,
          clip: {
            x: Math.max(0, dialogBox.x),
            y: Math.max(0, dialogBox.y),
            width: Math.min(dialogBox.width, 1280 - Math.max(0, dialogBox.x)),
            height: Math.min(dialogBox.height, 900 - Math.max(0, dialogBox.y)),
          },
        });
        console.log(`    ✅ Dialog clipped (${Math.round(dialogBox.width)}x${Math.round(dialogBox.height)})`);
      } else {
        // Fallback: full viewport screenshot
        await page.screenshot({ path: filepath });
        console.log(`    ✅ Full viewport (dialog surface not found)`);
      }
      captured++;

      // Close dialog
      await page.keyboard.press('Escape');
      await page.waitForTimeout(500);
    } catch (err) {
      console.log(`    ❌ Failed: ${err.message}`);
      failed++;
      try { await page.keyboard.press('Escape'); } catch (_) {}
      await page.waitForTimeout(500);
    }
  }

  await browser.close();
  console.log(`\nDone. ${captured} captured, ${failed} failed.`);
  console.log(`Screenshots: ${OUTPUT_DIR}/`);
}

main().catch(console.error);
