// Options page: one-time setup. The site switches ask the browser for access to
// Google Meet / Teams (optional host permissions); the background registers the call
// bridge there once allowed (background.js).
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

  // Each switch's origins, picked by host from the manifest's optional_host_permissions
  // (the one list; background.js's OPTIONAL must match it: sites.test.cjs). Teams needs
  // all its origins: permissions are all-or-nothing on the array.
  var HOSTS = { meet: /^meet\.google\.com$/, teams: /^teams\./ };
  var optional = api.runtime.getManifest().optional_host_permissions || [];
  function originsFor(site) {
    return optional.filter(function (origin) { return HOSTS[site].test(origin.split('/')[2] || ''); });
  }
  /**
   * A browser may grant the access yet refuse to register the site's script (the
   * background then can't start there): say so next to the switch rather than show
   * one that does nothing. Checked once the background has had time to register.
   */
  function checkRegistered(box) {
    var site = box.dataset.site;
    var note = box.parentNode.querySelector('.unavailable');
    setTimeout(function () {
      if (!box.checked) return;
      Promise.resolve(api.scripting.getRegisteredContentScripts()).then(function (list) {
        var ok = (list || []).some(function (s) { return s.id === 'vn-' + site; });
        note.hidden = ok;
        if (!ok) console.warn('VisioNext: ' + site + ' allowed, but this browser did not register its script');
      }, function () {});
    }, 500);
  }

  section.querySelectorAll('[data-site]').forEach(function (box) {
    var origins = originsFor(box.dataset.site);
    // Disabled until the real state is known: a click before that would act on a guess.
    box.disabled = true;
    Promise.resolve(api.permissions.contains({ origins: origins })).then(function (on) {
      box.checked = on;
      box.disabled = false;
      if (on) checkRegistered(box);
    }, function () { box.disabled = false; });
    box.addEventListener('change', function () {
      // Called straight from the click: browsers only prompt from a user gesture.
      var op = box.checked
        ? api.permissions.request({ origins: origins })
        : api.permissions.remove({ origins: origins });
      if (!box.checked) box.parentNode.querySelector('.unavailable').hidden = true;
      Promise.resolve(op).then(
        function (ok) {
          if (!ok) box.checked = !box.checked;
          else if (box.checked) checkRegistered(box);
        },
        function () { box.checked = !box.checked; }
      );
    });
  });
})();
