// Toolbar popup. The layout switch is backed by extension storage (layout-engine.js
// watches storage.onChanged and applies/removes live). The site switches ask the
// browser for access to Google Meet / Teams (optional host permissions); the
// background registers the call bridge there once allowed (background.js).
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

  // Keep in sync with OPTIONAL in background.js.
  var SITES = {
    meet: ['https://meet.google.com/*'],
    teams: ['https://teams.microsoft.com/*', 'https://teams.cloud.microsoft/*', 'https://teams.live.com/*'],
  };
  var section = document.getElementById('sites');
  if (!api || !api.permissions || !api.permissions.request || !api.scripting || !api.scripting.registerContentScripts) {
    section.hidden = true; // this browser can't opt sites in
    return;
  }
  section.querySelectorAll('[data-site]').forEach(function (box) {
    var origins = SITES[box.dataset.site];
    api.permissions.contains({ origins: origins }).then(function (on) { box.checked = on; });
    box.addEventListener('change', function () {
      // Called straight from the click: browsers only prompt from a user gesture.
      var op = box.checked
        ? api.permissions.request({ origins: origins })
        : api.permissions.remove({ origins: origins });
      Promise.resolve(op).then(
        function (ok) { if (!ok) box.checked = !box.checked; },
        function () { box.checked = !box.checked; }
      );
    });
  });
})();
