/*
 * VisioNext — adaptive participant-strip layout engine for Meet / LiveKit.
 *
 * Decides where the participant strip goes (beside or below the featured
 * screen/participant) and how many lines it uses, based on the shared content's
 * real aspect ratio — then writes a few hooks onto `.lk-focus-layout` that
 * enhance.css turns into the actual grid:
 *
 *   data-vn-place = "side" | "below"
 *   --vn-lines    = 1 | 2
 *   --vn-strip    = <px>
 *
 * The decision logic (decideLayout) is pure and unit-tested from Node; the DOM
 * controller below only runs in a browser. See the design doc:
 * docs/superpowers/specs/2026-07-02-meet-adaptive-layout-engine-design.md
 */
(function () {
  'use strict';

  var TILE_AR = 16 / 10; // LiveKit `.lk-carousel > *` aspect-ratio (width/height)

  /**
   * Pure layout decision. All inputs are numbers (px / ratio / count).
   *
   * Tries the strip below and beside the content, in 1..maxLines lines, and returns
   * the best as { place: 'below'|'side', lines, tileW, tileH, strip (px), overflow
   * (the strip scrolls), scale (content size against untouched, 0..1), visible
   * (tiles shown without scrolling) }. Best = everyone visible if any layout allows
   * it, then the largest content, then the most tiles shown, the biggest tiles, the
   * fewest lines.
   */
  function decideLayout(o) {
    var areaW = o.areaW, areaH = o.areaH;
    var count = Math.max(1, o.count | 0);
    var gap = o.gap != null ? o.gap : 8;
    var maxLines = o.maxLines != null ? o.maxLines : 3;
    var maxFraction = o.maxFraction != null ? o.maxFraction : 0.4;
    var minTileW = o.minTileW != null ? o.minTileW : 160;

    var known = !!(o.contentAR && isFinite(o.contentAR) && o.contentAR > 0);
    var cAR = known ? o.contentAR : areaW / areaH;
    // The content fitted to the whole area; the grey band is what it leaves.
    var fullW = Math.min(areaW, areaH * cAR), fullH = fullW / cAR;

    function candidate(place, lines) {
      var below = place === 'below';
      var lineLen = below ? areaW : areaH;       // the strip's lines run along this
      var depth = below ? areaH : areaW;         // and its thickness is taken from this
      var band = depth - (below ? fullH : fullW);
      var along = below ? 1 : 1 / TILE_AR;       // tile extent along a line, per px of tile width
      var across = below ? 1 / TILE_AR : 1;      // tile extent across a line, per px of tile width
      var perLine = Math.ceil(count / lines);
      var cap = maxFraction * depth;
      function widthFor(thickness) { return (thickness - (lines - 1) * gap) / lines / across; }

      // Minimum-size tiles may take up to the cap, or the whole band when it's bigger
      // (free space is never refused). One line is always an option.
      if (lines > 1 && widthFor(Math.max(cap, band - gap)) < minTileW) return null;
      var lineFit = (lineLen - (perLine - 1) * gap) / perLine / along;
      var fits = lineFit >= minTileW;
      // Grow only into the band, up to the cap; never below the minimum (the content
      // shrinks instead).
      var w = fits ? Math.min(lineFit, Math.max(minTileW, widthFor(Math.min(cap, band - gap)))) : minTileW;
      var tileW = Math.floor(w + 1e-6), tileH = Math.floor(tileW / TILE_AR + 1e-6);

      var strip = lines * (below ? tileH : tileW) + (lines - 1) * gap;
      var boxW = below ? areaW : areaW - strip - gap;
      var boxH = below ? areaH - strip - gap : areaH;
      var shownPerLine = Math.floor((lineLen + gap) / ((below ? tileW : tileH) + gap));
      return {
        place: place, lines: lines, tileW: tileW, tileH: tileH, strip: strip,
        overflow: !fits,
        scale: Math.round(Math.max(0, Math.min(1, boxW / fullW, boxH / fullH)) * 1000) / 1000,
        visible: Math.min(count, shownPerLine * lines),
      };
    }

    function better(a, b) {
      if (a.scale !== b.scale) return a.scale > b.scale;
      if (a.visible !== b.visible) return a.visible > b.visible;
      if (a.tileW !== b.tileW) return a.tileW > b.tileW;
      return a.lines < b.lines;
    }

    var fitting = [], scrolling = [];
    ['below', 'side'].forEach(function (place) {
      var most = null; // this place's scrolling layout with the most lines
      for (var lines = 1; lines <= maxLines; lines++) {
        var c = candidate(place, lines);
        if (!c) break; // more lines take even more room
        if (c.overflow) most = c; else fitting.push(c);
      }
      if (most) scrolling.push(most);
    });
    // Nobody fits: each place scrolls with its most lines (so the strip doesn't
    // fall back to one line as people join), and the content picks the place.
    var pool = fitting.length ? fitting : scrolling;
    return pool.reduce(function (best, c) { return better(c, best) ? c : best; });
  }

  // Export the pure part for the Node test; harmless in the browser.
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { decideLayout: decideLayout };
  }

  // ---- DOM controller (browser only) --------------------------------------
  if (typeof document === 'undefined') return;

  var CONFIG = { minTileW: 132, minTileH: 100, maxLines: 2, maxFraction: 0.35 };
  var current = null;   // the bound .lk-focus-layout element
  var ro = null;        // ResizeObserver on it
  var scheduled = false;
  var enabled = false;  // gated on the stored setting (default on); see bootstrap
  var boundVideos = (typeof WeakSet !== 'undefined') ? new WeakSet() : null;

  // Extension storage API (chrome/browser); null in a plain page (bookmarklet).
  var store = (function () {
    var b = (typeof browser !== 'undefined') ? browser
      : (typeof chrome !== 'undefined') ? chrome : null;
    return (b && b.storage && b.storage.local) ? b.storage : null;
  })();

  function gap(el) {
    var v = parseFloat(getComputedStyle(el).getPropertyValue('--lk-grid-gap'));
    return isFinite(v) ? v : 8;
  }

  function setVar(el, name, value) {
    if (el.style.getPropertyValue(name) !== String(value)) {
      el.style.setProperty(name, String(value));
    }
  }

  function apply(focus, d) {
    if (focus.dataset.vnPlace !== d.place) focus.dataset.vnPlace = d.place;
    setVar(focus, '--vn-lines', d.lines);
    setVar(focus, '--vn-strip', d.strip + 'px');
  }

  function clearHooks(focus) {
    delete focus.dataset.vnPlace;
    focus.style.removeProperty('--vn-lines');
    focus.style.removeProperty('--vn-strip');
  }

  function recompute() {
    scheduled = false;
    var focus = current;
    if (!focus || !focus.isConnected) return;
    var rect = focus.getBoundingClientRect();
    if (!rect.width || !rect.height) return;

    var aside = focus.querySelector(':scope > aside.lk-carousel');
    var count = aside ? aside.querySelectorAll(':scope > .lk-participant-tile').length : 0;
    if (!aside || count === 0) { clearHooks(focus); return; }

    var featured = focus.querySelector(':scope > .lk-participant-tile');
    var video = featured ? featured.querySelector('video') : null;
    if (video && boundVideos && !boundVideos.has(video)) {
      boundVideos.add(video);
      video.addEventListener('resize', schedule);
      video.addEventListener('loadedmetadata', schedule);
    }
    var contentAR = (video && video.videoWidth && video.videoHeight)
      ? video.videoWidth / video.videoHeight : null;

    apply(focus, decideLayout({
      areaW: rect.width, areaH: rect.height, contentAR: contentAR, count: count,
      gap: gap(focus), minTileW: CONFIG.minTileW, minTileH: CONFIG.minTileH,
      maxLines: CONFIG.maxLines, maxFraction: CONFIG.maxFraction,
    }));
  }

  function schedule() {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(recompute);
  }

  var mo = new MutationObserver(schedule); // tiles added/removed within focus

  function bind(focus) {
    if (current === focus) return;
    unbind();
    current = focus;
    ro = new ResizeObserver(schedule);
    ro.observe(focus);
    mo.observe(focus, { childList: true, subtree: true });
    schedule();
  }

  function unbind() {
    if (ro) { ro.disconnect(); ro = null; }
    mo.disconnect();
    if (current) clearHooks(current);
    current = null;
  }

  function scan() {
    if (!enabled) { unbind(); return; }
    var focus = document.querySelector('.lk-focus-layout');
    if (focus) bind(focus);
    else unbind();
  }

  function setEnabled(on) {
    enabled = !!on;
    document.documentElement.classList.toggle('vn-on', enabled);
    scan(); // binds when enabled, unbinds + clears hooks when not
  }

  // Watch the SPA: the room (and focus layout) mounts/unmounts over time.
  var rootMo = new MutationObserver(function () {
    if (enabled && (!current || !current.isConnected)) scan();
  });
  rootMo.observe(document.documentElement, { childList: true, subtree: true });
  window.addEventListener('resize', schedule);

  // On/off is stored (default on) and driven from the toolbar popup; a plain page
  // (bookmarklet) has no storage, so it just turns on.
  if (store) {
    store.local.get('enabled')
      .then(function (r) { setEnabled(r.enabled !== false); })
      .catch(function () { setEnabled(true); });
    if (store.onChanged) {
      store.onChanged.addListener(function (ch, area) {
        if (area === 'local' && ch.enabled) setEnabled(ch.enabled.newValue !== false);
      });
    }
  } else {
    setEnabled(true);
  }

  // Teardown handle (used by the bookmarklet to toggle off).
  window.__vnMeet = {
    config: CONFIG,
    setEnabled: setEnabled,
    stop: function () {
      rootMo.disconnect();
      window.removeEventListener('resize', schedule);
      unbind();
      document.documentElement.classList.remove('vn-on');
      delete window.__vnMeet;
    },
    recompute: schedule,
  };
})();
