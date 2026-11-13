// The layout in a real browser: loads layout-gallery.html in headless Chromium (or
// Chrome) and checks every mocked screen share it reports. Run: node --test
// Skipped when no browser is found; point $CHROMIUM at one to choose.
const { test } = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const { existsSync } = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { decideLayout } = require('./layout-engine.js');

const BROWSER = [
  process.env.CHROMIUM,
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
].find((p) => p && existsSync(p));

function runGallery() {
  const url = pathToFileURL(path.join(__dirname, 'layout-gallery.html')).href;
  // The window fits every thumbnail: offscreen frames don't run, so wouldn't report.
  const html = execFileSync(BROWSER, [
    '--headless', '--disable-gpu', '--autoplay-policy=no-user-gesture-required',
    '--window-size=1800,3600', '--virtual-time-budget=20000', '--dump-dom', url,
  ], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'], timeout: 120000 });
  const m = /<pre id="results" data-expected="(\d+)">([^<]*)<\/pre>/.exec(html);
  assert.ok(m, 'the gallery has no results');
  const text = m[2].replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
  return { expected: +m[1], results: text ? JSON.parse(text) : [] };
}

test('layout in a real browser', { skip: !BROWSER && 'no Chromium or Chrome found (set $CHROMIUM)' }, async (t) => {
  const { expected, results } = runGallery();
  assert.equal(results.length, expected, 'every case reported');

  for (const r of results) {
    await t.test(r.id, () => {
      const [, w, h] = /^(\d+)x(\d+)/.exec(r.id);
      assert.deepEqual([r.area.w, r.area.h, r.gap], [+w, +h, 8], 'the mock call has its labelled size and LiveKit gap');
      assert.deepEqual(r.problems, []);

      // The controller measured the content box and gap, and the CSS drew its decision.
      const d = decideLayout({ areaW: r.area.w, areaH: r.area.h, contentAR: r.ar, count: r.n, gap: r.gap });
      assert.deepEqual(
        { place: r.place, lines: r.lines, tileW: r.tileW, tileH: r.tileH },
        { place: d.place, lines: d.lines, tileW: d.tileW, tileH: d.tileH });
      assert.equal(r.scrolls, d.overflow, 'the strip scrolls exactly when the engine says it overflows');

      // The shared screen gets all the space the strip leaves.
      const boxW = d.place === 'below' ? r.area.w : r.area.w - d.strip - r.gap;
      const boxH = d.place === 'below' ? r.area.h - d.strip - r.gap : r.area.h;
      const shownW = Math.min(r.video.w, r.video.h * r.ar);
      assert.ok(Math.abs(shownW - Math.min(boxW, boxH * r.ar)) <= 1,
        `shared screen shown ${shownW.toFixed(1)}px wide, expected ${Math.min(boxW, boxH * r.ar).toFixed(1)}`);
    });
  }
});
