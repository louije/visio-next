// Toolbar popup: what's used day to day — the layout switch, backed by extension
// storage (layout-engine.js watches storage.onChanged and applies/removes live).
// One-time setup (global mute on Google Meet / Teams) is on the options page.
(function () {
  'use strict';
  var api = (typeof browser !== 'undefined') ? browser
    : (typeof chrome !== 'undefined') ? chrome : null;

  var toggle = document.getElementById('toggle');
  if (!api || !api.storage) {
    toggle.disabled = true;
  } else {
    api.storage.local.get('enabled').then(function (r) {
      toggle.checked = r.enabled !== false; // default on
    });
    toggle.addEventListener('change', function () {
      api.storage.local.set({ enabled: toggle.checked });
    });
  }

  var settings = document.getElementById('settings');
  if (!api || !api.runtime || !api.runtime.openOptionsPage) {
    settings.hidden = true;
    return;
  }
  settings.addEventListener('click', function (e) {
    e.preventDefault();
    api.runtime.openOptionsPage();
    window.close();
  });
})();
