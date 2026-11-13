// Unit tests for the pure layout decision. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const { decideLayout } = require('./layout-engine.js');

const TILE_AR = 16 / 10;
const GAP = 8, MAX_LINES = 3, MAX_FRACTION = 0.4;
const MIN_W = 160, MIN_H = 100;          // the tile size we keep when it shows everyone
const SQUEEZE_W = 128, SQUEEZE_H = 80;   // the smaller size allowed when that's what fits everyone

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

// Whether `lines` lines of tiles `tileW` wide, beside/below, hold `count` people
// within a strip thickness of `room`.
function tilesHold(place, lines, count, areaW, areaH, room, tileW) {
  const tileH = tileW / TILE_AR;
  const perLine = Math.ceil(count / lines);
  const lineLen = place === 'below' ? areaW : areaH;
  const along = place === 'below' ? tileW : tileH;
  const across = place === 'below' ? tileH : tileW;
  return perLine * along + (perLine - 1) * GAP <= lineLen &&
    lines * across + (lines - 1) * GAP <= room;
}

// The thickness a strip of `lines` lines may take: up to three lines may take the
// 40% cap or the whole grey band, whichever is bigger; more lines only the band.
function room(place, lines, areaW, areaH, full) {
  const band = full.band[place] - GAP;
  return lines <= MAX_LINES ? Math.max(MAX_FRACTION * (place === 'below' ? areaH : areaW), band) : band;
}

// Every (place, lines) whose tiles of `tileW` hold everyone within their room.
function holding(count, areaW, areaH, full, tileW, roomFor = room) {
  const found = [];
  for (const place of ['below', 'side']) {
    for (let lines = 1; lines <= count; lines++) {
      if (tilesHold(place, lines, count, areaW, areaH, roomFor(place, lines, areaW, areaH, full), tileW)) found.push([place, lines]);
    }
  }
  return found;
}
const inBand = (place, lines, areaW, areaH, full) => full.band[place] - GAP;

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

test('a tall Notion window with 50 people -> five columns of smaller tiles in the band, everyone visible', () => {
  const d = decideLayout({ areaW: 1411, areaH: 893, contentAR: 0.6, count: 50, gap: GAP });
  assert.deepEqual([d.place, d.lines, d.overflow], ['side', 5, false]);
  assert.deepEqual([d.tileW, d.tileH], [SQUEEZE_W, SQUEEZE_H]);
  assert.equal(shown(1411, 893, 0.6, d), 1);
});

test('the same on a laptop with the chat open -> it scrolls, using the whole band, at the usual size', () => {
  const d = decideLayout({ areaW: 1280, areaH: 620, contentAR: 0.6, count: 50, gap: GAP });
  assert.deepEqual([d.place, d.overflow, d.tileW], ['side', true, MIN_W]);
  assert.ok(d.lines > MAX_LINES, `${d.lines} columns fill the band`);
  assert.equal(shown(1280, 620, 0.6, d), 1);
});

test('a scrolling strip makes room for a visible scrollbar; one that fits needs none', () => {
  const scrolling = decideLayout({ areaW: 1411, areaH: 893, contentAR: 16 / 10, count: 50, gap: GAP, scrollbar: 15 });
  assert.equal(scrolling.overflow, true);
  const across = scrolling.place === 'below' ? scrolling.tileH : scrolling.tileW;
  assert.equal(scrolling.strip, scrolling.lines * across + (scrolling.lines - 1) * GAP + 15);
  const fitting = { areaW: 1411, areaH: 893, contentAR: 2.58, count: 4, gap: GAP };
  assert.deepEqual(decideLayout({ ...fitting, scrollbar: 15 }), decideLayout(fitting));
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
// screen, a narrow window, a huge screen. Shared screens: phone, a tall Notion
// window, portrait window, 4:3, 16:10, 16:9, 21:9, the wide tab of the screenshot,
// a 32:9 ultrawide.
const AREAS = [[1411, 893], [1280, 620], [1880, 960], [900, 800], [2400, 1200]];
const RATIOS = [9 / 16, 0.6, 3 / 4, 4 / 3, 16 / 10, 16 / 9, 21 / 9, 2.58, 32 / 9];

// Scrollbars: overlay (macOS with a trackpad) or always visible (a mouse, Windows).
for (const scrollbar of [0, 15])
for (const [areaW, areaH] of AREAS) {
  for (const ar of RATIOS) {
    test(`sweep: ${areaW}x${areaH}, shared screen ${ar.toFixed(2)}:1, 2 to 50 people, ${scrollbar}px scrollbars`, () => {
      const full = fullFit(areaW, areaH, ar);
      let prev = null;
      for (let count = 2; count <= 50; count++) {
        const d = decideLayout({ areaW, areaH, contentAR: ar, count, gap: GAP, scrollbar });
        const at = ` (${count} people: ${JSON.stringify(d)})`;
        const bar = d.overflow ? scrollbar : 0;   // a scrolling strip also holds its scrollbar
        const below = d.place === 'below';
        const lineLen = below ? areaW : areaH;
        const along = below ? d.tileW : d.tileH;
        const across = below ? d.tileH : d.tileW;

        assert.ok(d.tileW >= SQUEEZE_W && d.tileH >= SQUEEZE_H, 'tiles at least the smaller size' + at);
        assert.ok(Math.abs(d.tileW / d.tileH - TILE_AR) < 0.02, 'tiles keep 16:10' + at);
        assert.equal(d.strip, d.lines * across + (d.lines - 1) * GAP + bar, 'the strip is its lines (and scrollbar)' + at);
        assert.ok(d.strip - bar <= room(d.place, d.lines, areaW, areaH, full) + 1e-9,
          'the strip stays within its room (more than three lines only in the band)' + at);

        const perLine = Math.floor((lineLen + GAP) / (along + GAP));
        assert.equal(d.overflow, perLine * d.lines < count, 'scrolls exactly when its lines cannot hold everyone' + at);

        const usual = holding(count, areaW, areaH, full, MIN_W);
        const squeezed = holding(count, areaW, areaH, full, SQUEEZE_W);
        if (squeezed.length) assert.equal(d.overflow, false, 'nobody scrolls when some layout holds everyone' + at);
        if (usual.length) assert.ok(d.tileW >= MIN_W, 'the usual tile size when it holds everyone' + at);
        if (d.tileW < MIN_W) assert.ok(!d.overflow && !usual.length, 'smaller tiles only when they are what fits everyone' + at);
        if (d.overflow) assert.ok(d.tileW >= MIN_W, 'a scrolling strip keeps the usual tile size' + at);

        // The content is as big as with any layout that holds everyone at the size used.
        for (const [p, l] of usual.length ? usual : squeezed) {
          const tile = usual.length ? { w: MIN_W, h: MIN_H } : { w: SQUEEZE_W, h: SQUEEZE_H };
          const strip = l * (p === 'below' ? tile.h : tile.w) + (l - 1) * GAP;
          const theirs = shown(areaW, areaH, ar, { place: p, strip });
          assert.ok(shown(areaW, areaH, ar, d) >= theirs - 0.001,
            `content as big as with ${l} line(s) ${p} at ${tile.w}px (${theirs.toFixed(3)})` + at);
        }
        const bandHolds = holding(count, areaW, areaH, full, usual.length ? MIN_W : SQUEEZE_W, inBand).length > 0;
        if (bandHolds) assert.equal(shown(areaW, areaH, ar, d), 1, 'content untouched when the grey band holds everyone' + at);

        if (prev && prev.overflow === d.overflow) {
          assert.ok(d.tileW <= prev.tileW, `tiles never grow with more people (were ${prev.tileW}px)` + at);
        }
        prev = d;
      }
    });
  }
}
