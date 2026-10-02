// Options page: one-time setup. The site switches ask the browser for access to
// Google Meet / Teams (optional host permissions); the background registers the call
// bridge there once allowed (sites.js, loaded before this file).
(function () {
  'use strict';
  var api = (typeof browser !== 'undefined') ? browser
    : (typeof chrome !== 'undefined') ? chrome : null;

  var section = document.getElementById('sites');
  if (!api || !api.permissions || !api.permissions.request || !api.scripting || !api.scripting.registerContentScripts) {
    section.hidden = true;
    document.getElementById('unsupported').hidden = false;
    return;
  }

  var OPTIONAL = (globalThis.VNSites && globalThis.VNSites.OPTIONAL) || [];
  function originsFor(id) {
    for (var k = 0; k < OPTIONAL.length; k++) if (OPTIONAL[k].id === id) return OPTIONAL[k].origins;
    return [];
  }

  var boxes = [].slice.call(section.querySelectorAll('[data-site]'));

  // Sites allowed but that this browser refused to register (the background records
  // them in storage.local.unavailable): say so next to a switch that is on, rather
  // than show one that does nothing.
  var unavailable = [];
  function showNotes() {
    boxes.forEach(function (box) {
      box.parentNode.querySelector('.unavailable').hidden =
        !box.checked || unavailable.indexOf(box.dataset.site) < 0;
    });
  }
  if (api.storage && api.storage.local) {
    Promise.resolve(api.storage.local.get('unavailable')).then(function (r) {
      unavailable = (r && r.unavailable) || [];
      showNotes();
    }, function () {});
    api.storage.onChanged.addListener(function (changes, area) {
      if (area !== 'local' || !changes.unavailable) return;
      unavailable = changes.unavailable.newValue || [];
      showNotes();
    });
  }

  boxes.forEach(function (box) {
    var origins = originsFor(box.dataset.site);
    // Disabled until the real state is known: a click before that would act on a guess.
    box.disabled = true;
    if (!origins.length) { // a switch with no site behind it: never usable
      console.warn('VisioNext: no origins for the ' + box.dataset.site + ' switch');
      return;
    }
    Promise.resolve(api.permissions.contains({ origins: origins })).then(function (on) {
      box.checked = on;
      box.disabled = false;
      showNotes();
    }, function () { box.disabled = false; });
    box.addEventListener('change', function () {
      // Called straight from the click: browsers only prompt from a user gesture.
      var op = box.checked
        ? api.permissions.request({ origins: origins })
        : api.permissions.remove({ origins: origins });
      showNotes();
      Promise.resolve(op).then(
        function (ok) { if (!ok) box.checked = !box.checked; showNotes(); },
        function () { box.checked = !box.checked; showNotes(); }
      );
    });
  });
})();
