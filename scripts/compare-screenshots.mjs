#!/usr/bin/env node
/**
 * Compares HA web screenshots against app snapshot references.
 *
 * This produces a parity report — NOT a pass/fail test. The HA web renders
 * and the native iOS app renders will always differ (different rendering engines,
 * fonts, spacing). The goal is to measure visual similarity and track it over time.
 *
 * Comparison modes:
 *   1. HA web view screenshots vs previous HA web captures (regression)
 *   2. HA web section screenshots vs app snapshot references (parity measurement)
 *
 * Usage:
 *   node compare-screenshots.mjs                        # Compare latest captures
 *   node compare-screenshots.mjs --baseline <dir>       # Compare against baseline
 *   node compare-screenshots.mjs --app-refs <dir>       # Compare against app refs
 */
import { readFileSync, readdirSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { PNG } from 'pngjs';
import pixelmatch from 'pixelmatch';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const SCREENSHOTS_DIR = path.join(__dirname, '..', 'screenshots', 'ha-web');
const BASELINE_DIR = process.argv.includes('--baseline')
  ? process.argv[process.argv.indexOf('--baseline') + 1]
  : path.join(__dirname, '..', 'screenshots', 'baseline');
const APP_REFS_DIR = process.argv.includes('--app-refs')
  ? process.argv[process.argv.indexOf('--app-refs') + 1]
  : path.join(__dirname, '..', 'HADashboardTests', 'ReferenceImages_64');
const DIFF_DIR = path.join(__dirname, '..', 'screenshots', 'diffs');

function loadPNG(filepath) {
  const data = readFileSync(filepath);
  return PNG.sync.read(data);
}

function comparePair(img1Path, img2Path, diffPath) {
  const img1 = loadPNG(img1Path);
  const img2 = loadPNG(img2Path);

  // If images are different sizes, resize the smaller to match
  const width = Math.min(img1.width, img2.width);
  const height = Math.min(img1.height, img2.height);

  // Create cropped versions if sizes differ
  const crop = (img, w, h) => {
    if (img.width === w && img.height === h) return img.data;
    const cropped = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) {
      const srcOffset = y * img.width * 4;
      const dstOffset = y * w * 4;
      img.data.copy(cropped, dstOffset, srcOffset, srcOffset + w * 4);
    }
    return cropped;
  };

  const data1 = crop(img1, width, height);
  const data2 = crop(img2, width, height);

  const diff = new PNG({ width, height });
  const mismatchedPixels = pixelmatch(data1, data2, diff.data, width, height, {
    threshold: 0.3,  // Generous threshold — we're measuring similarity not pixel-exact
    alpha: 0.3,
    diffColor: [255, 0, 128],
    diffColorAlt: [0, 200, 255],
  });

  // Save diff image
  if (diffPath) {
    mkdirSync(path.dirname(diffPath), { recursive: true });
    writeFileSync(diffPath, PNG.sync.write(diff));
  }

  const totalPixels = width * height;
  const matchPercent = ((1 - mismatchedPixels / totalPixels) * 100).toFixed(1);
  const sizeDiffers = img1.width !== img2.width || img1.height !== img2.height;

  return {
    matchPercent: parseFloat(matchPercent),
    mismatchedPixels,
    totalPixels,
    sizeDiffers,
    img1Size: `${img1.width}x${img1.height}`,
    img2Size: `${img2.width}x${img2.height}`,
  };
}

function compareWebRegression() {
  console.log('=== HA Web Regression (current vs baseline) ===\n');

  if (!existsSync(BASELINE_DIR)) {
    console.log(`No baseline found at ${BASELINE_DIR}`);
    console.log('Run with current screenshots as baseline:');
    console.log(`  cp -r ${SCREENSHOTS_DIR} ${BASELINE_DIR}\n`);
    return [];
  }

  const currentFiles = readdirSync(SCREENSHOTS_DIR).filter(f => f.endsWith('.png'));
  const results = [];

  for (const file of currentFiles) {
    const baselinePath = path.join(BASELINE_DIR, file);
    if (!existsSync(baselinePath)) {
      console.log(`  NEW: ${file} (no baseline)`);
      results.push({ file, status: 'new', matchPercent: null });
      continue;
    }

    const currentPath = path.join(SCREENSHOTS_DIR, file);
    const diffPath = path.join(DIFF_DIR, 'regression', file);
    const result = comparePair(currentPath, baselinePath, diffPath);

    const status = result.matchPercent >= 99.0 ? 'PASS' : result.matchPercent >= 90.0 ? 'WARN' : 'DIFF';
    const sizeNote = result.sizeDiffers ? ` [size: ${result.img1Size} vs ${result.img2Size}]` : '';
    console.log(`  ${status}: ${file} — ${result.matchPercent}% match${sizeNote}`);

    results.push({ file, status, ...result });
  }

  return results;
}

function compareAppParity() {
  console.log('\n=== App Parity (HA web vs iOS app references) ===\n');

  if (!existsSync(APP_REFS_DIR)) {
    console.log(`No app references found at ${APP_REFS_DIR}`);
    return [];
  }

  // Find all app reference images recursively
  const appRefs = [];
  const walkDir = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        walkDir(path.join(dir, entry.name));
      } else if (entry.name.endsWith('.png')) {
        appRefs.push({
          fullPath: path.join(dir, entry.name),
          name: entry.name,
          suite: path.basename(dir),
        });
      }
    }
  };
  walkDir(APP_REFS_DIR);

  console.log(`Found ${appRefs.length} app reference images across ${new Set(appRefs.map(r => r.suite)).size} suites.`);

  // Map HA web section screenshots to app reference images by domain/type
  const haFiles = readdirSync(SCREENSHOTS_DIR).filter(f => f.startsWith('section-'));

  // Build a mapping of view sections to approximate app test suites
  const viewToSuite = {
    'lighting': ['HALightingSnapshotTests'],
    'climate': ['HAClimateSnapshotTests'],
    'sensors': ['HASensorSnapshotTests', 'HACompositeSnapshotTests'],
    'security': ['HAControlSnapshotTests'],
    'media': [],  // media-control card — compare manually
    'vacuums': ['HAControlSnapshotTests'],
    'inputs': ['HAInputSnapshotTests'],
    'entities': ['HACompositeSnapshotTests'],
  };

  const results = [];

  for (const haFile of haFiles) {
    // Extract view name from filename: section-lighting-0.png -> lighting
    const match = haFile.match(/^section-(\w+)-(\d+)\.png$/);
    if (!match) continue;
    const [, viewName, sectionIdx] = match;
    const suites = viewToSuite[viewName] || [];

    console.log(`\n  ${haFile} → maps to suites: ${suites.join(', ') || '(none)'}`);

    // For now, just list which app refs exist for this domain
    for (const suite of suites) {
      const suiteRefs = appRefs.filter(r => r.suite === suite);
      if (suiteRefs.length > 0) {
        console.log(`    ${suite}: ${suiteRefs.length} reference images`);
      }
    }

    results.push({ haFile, viewName, sectionIdx: parseInt(sectionIdx), suites });
  }

  return results;
}

function generateReport(regressionResults, parityResults) {
  const reportPath = path.join(__dirname, '..', 'screenshots', 'comparison-report.md');

  const lines = [
    '# Visual Comparison Report',
    `Generated: ${new Date().toISOString()}`,
    '',
    '## HA Web Regression (current vs baseline)',
    '',
  ];

  if (regressionResults.length === 0) {
    lines.push('No baseline available. Establish one with:');
    lines.push('```');
    lines.push(`cp -r screenshots/ha-web screenshots/baseline`);
    lines.push('```');
  } else {
    lines.push('| File | Match | Status |');
    lines.push('|------|-------|--------|');
    for (const r of regressionResults) {
      lines.push(`| ${r.file} | ${r.matchPercent ?? 'N/A'}% | ${r.status} |`);
    }

    const passing = regressionResults.filter(r => r.status === 'PASS').length;
    const warning = regressionResults.filter(r => r.status === 'WARN').length;
    const diff = regressionResults.filter(r => r.status === 'DIFF').length;
    lines.push('', `**Summary**: ${passing} pass, ${warning} warn, ${diff} diff`);
  }

  lines.push('', '## App Parity Mapping', '');
  lines.push('| HA Section | View | App Test Suites |');
  lines.push('|------------|------|-----------------|');
  for (const p of parityResults) {
    lines.push(`| ${p.haFile} | ${p.viewName} | ${p.suites.join(', ') || '—'} |`);
  }

  lines.push('', '## Next Steps', '');
  lines.push('1. Establish baseline: `cp -r screenshots/ha-web screenshots/baseline`');
  lines.push('2. After app changes, re-capture and compare');
  lines.push('3. Individual section-to-cell comparisons require manual cropping');
  lines.push('   (HA sections contain multiple cards; app snapshots are per-cell)');
  lines.push('');

  writeFileSync(reportPath, lines.join('\n'));
  console.log(`\nReport written to: ${reportPath}`);
}

// Main
console.log('HA Test Harness Visual Comparison\n');

if (!existsSync(SCREENSHOTS_DIR)) {
  console.error(`No screenshots found at ${SCREENSHOTS_DIR}`);
  console.error('Run capture first: npm run capture');
  process.exit(1);
}

const regressionResults = compareWebRegression();
const parityResults = compareAppParity();
generateReport(regressionResults, parityResults);
