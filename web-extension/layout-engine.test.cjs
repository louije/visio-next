// Unit tests for the pure layout decision. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const { decideLayout } = require('./layout-engine.js');

const TILE_AR = 16 / 10;
const MIN_W = 160, MIN_H = 100, GAP = 8, MAX_LINES = 3, MAX_FRACTION = 0.4;

// The content fitted to the whole area: its size, and the grey band it leaves
// below it and beside it.
function fullFit(areaW, areaH, ar) {
  const w = Math.min(areaW, areaH * ar), h = w / ar;
  return { w, h, band: { below: areaH - h, side: areaW - w } };
}

// How big the content is shown next to the strip, against its full-area fit (1 =
// untouched). Computed here from the strip, not taken from the engine.
function shown(areaW, areaH, ar, d) {
  const full = fullFit(areaW, areaH, ar);
  const boxW = d.place === 'below' ? areaW : areaW - d.strip - GAP;
  const boxH = d.place === 'below' ? areaH - d.strip - GAP : areaH;
  return Math.min(1, boxW / full.w, boxH / full.h);
}

// Whether `lines` lines of minimum-size tiles beside/below hold `count` people
// within a thickness of `room`.
function minTilesHold(place, lines, count, areaW, areaH, room) {
  const perLine = Math.ceil(count / lines);
  const lineLen = place === 'below' ? areaW : areaH;
  const along = place === 'below' ? MIN_W : MIN_H;
  const across = place === 'below' ? MIN_H : MIN_W;
  return perLine * along + (perLine - 1) * GAP <= lineLen &&
    lines * across + (lines - 1) * GAP <= room;
}

const LAYOUTS = [];
for (const place of ['below', 'side']) for (let lines = 1; lines <= MAX_LINES; lines++) LAYOUTS.push([place, lines]);

test('the reported screenshot: a wide tab and 4 people -> one row below, content untouched', () => {
  const d = decideLayout({ areaW: 1411, areaH: 893, contentAR: 2.58, count: 4, gap: GAP });
  assert.equal(d.place, 'below');
  assert.equal(d.lines, 1);
  assert.equal(d.overflow, false);
  assert.ok(4 * d.tileW + 3 * GAP <= 1411, `4 tiles of ${d.tileW}px fit the width`);
  assert.ok(4 * (d.tileW + 1) + 3 * GAP > 1411, `4 tiles of ${d.tileW}px fill the row`);
  assert.equal(shown(1411, 893, 2.58, d), 1);
});

test('no grey band: tiles at their minimum, the content shrinks to make room', () => {
  const d = decideLayout({ areaW: 1600, areaH: 1000, contentAR: 16 / 10, count: 4, gap: GAP });
  assert.equal(d.tileW, MIN_W);
  assert.ok(shown(1600, 1000, 16 / 10, d) < 1);
});

test('a phone-shaped share with 20 people -> three columns in the side band', () => {
  const d = decideLayout({ areaW: 1411, areaH: 893, contentAR: 9 / 16, count: 20, gap: GAP });
  assert.deepEqual([d.place, d.lines, d.overflow], ['side', 3, false]);
  assert.equal(shown(1411, 893, 9 / 16, d), 1);
});

test('an ultrawide share in a short window with 20 people -> three rows in the band, past the cap', () => {
  // 3 rows (316px) exceed 40% of 700px, but the 32:9 screen leaves a 340px band
  const d = decideLayout({ areaW: 1280, areaH: 700, contentAR: 32 / 9, count: 20, gap: GAP });
  assert.deepEqual([d.place, d.lines, d.overflow], ['below', 3, false]);
  assert.equal(shown(1280, 700, 32 / 9, d), 1);
});

test('more people than fit at minimum size -> the strip scrolls, with its most lines', () => {
  const d = decideLayout({ areaW: 1411, areaH: 893, contentAR: 16 / 10, count: 50, gap: GAP });
  assert.equal(d.overflow, true);
  assert.equal(d.lines, MAX_LINES);
  assert.equal(d.tileW, MIN_W);
});

test('an unknown content ratio is laid out as content filling the area', () => {
  const unknown = decideLayout({ areaW: 1411, areaH: 893, contentAR: null, count: 6, gap: GAP });
  const filling = decideLayout({ areaW: 1411, areaH: 893, contentAR: 1411 / 893, count: 6, gap: GAP });
  assert.deepEqual(unknown, filling);
});

// Focus areas: the reported screenshot, a laptop with the chat panel open, a big
// screen, a narrow window, a huge screen. Shared screens: phone, portrait window,
// 4:3, 16:10, 16:9, 21:9, the wide tab of the screenshot, a 32:9 ultrawide.
const AREAS = [[1411, 893], [1280, 620], [1880, 960], [900, 800], [2400, 1200]];
const RATIOS = [9 / 16, 3 / 4, 4 / 3, 16 / 10, 16 / 9, 21 / 9, 2.58, 32 / 9];

for (const [areaW, areaH] of AREAS) {
  for (const ar of RATIOS) {
    test(`sweep: ${areaW}x${areaH}, shared screen ${ar.toFixed(2)}:1, 2 to 50 people`, () => {
      const full = fullFit(areaW, areaH, ar);
      let prev = null;
      for (let count = 2; count <= 50; count++) {
        const d = decideLayout({ areaW, areaH, contentAR: ar, count, gap: GAP });
        const at = ` (${count} people: ${JSON.stringify(d)})`;
        const below = d.place === 'below';
        const lineLen = below ? areaW : areaH;
        const depth = below ? areaH : areaW;
        const along = below ? d.tileW : d.tileH;
        const across = below ? d.tileH : d.tileW;
        const room = Math.max(MAX_FRACTION * depth, full.band[d.place] - GAP);

        assert.ok(d.lines >= 1 && d.lines <= MAX_LINES, 'one to three lines' + at);
        assert.ok(d.tileW >= MIN_W && d.tileH >= MIN_H, 'tiles at least the minimum' + at);
        assert.ok(Math.abs(d.tileW / d.tileH - TILE_AR) < 0.02, 'tiles keep 16:10' + at);
        assert.equal(d.strip, d.lines * across + (d.lines - 1) * GAP, 'the strip is its lines' + at);
        assert.ok(d.strip <= room + 1e-9, 'the strip stays within the cap or the band' + at);

        const perLine = Math.floor((lineLen + GAP) / (along + GAP));
        assert.equal(d.overflow, perLine * d.lines < count, 'scrolls exactly when its lines cannot hold everyone' + at);

        const holding = LAYOUTS.filter(([p, l]) => minTilesHold(p, l, count, areaW, areaH,
          Math.max(MAX_FRACTION * (p === 'below' ? areaH : areaW), full.band[p] - GAP)));
        if (holding.length) assert.equal(d.overflow, false, 'nobody scrolls when some layout holds everyone' + at);
        for (const [p, l] of holding) {
          const minStrip = l * (p === 'below' ? MIN_H : MIN_W) + (l - 1) * GAP;
          const theirs = shown(areaW, areaH, ar, { place: p, strip: minStrip });
          assert.ok(shown(areaW, areaH, ar, d) >= theirs - 0.001,
            `content as big as with ${l} line(s) ${p} at minimum size (${theirs.toFixed(3)})` + at);
        }

        const bandHolds = LAYOUTS.some(([p, l]) => minTilesHold(p, l, count, areaW, areaH, full.band[p] - GAP));
        if (bandHolds) assert.equal(shown(areaW, areaH, ar, d), 1, 'content untouched when the grey band holds everyone' + at);

        if (prev) assert.ok(d.tileW <= prev.tileW, `tiles never grow with more people (were ${prev.tileW}px)` + at);
        prev = d;
      }
    });
  }
}
