/*
 * VisioNext — the call sites, in one place: which origins, which scripts, and how the
 * opted-in ones get registered, injected and stopped.
 *
 * Loaded before background.js (importScripts in a service worker, manifest
 * `background.scripts` in Firefox) and before options.js on the options page; exposed
 * as `globalThis.VNSites`. Visio is always on (manifest host_permissions and static
 * content script); Google Meet and Teams are opt-in (optional host permissions).
 * sites.test.cjs checks these lists against manifest.json and providers/*.js.
 */
(function () {
  'use strict';
  if (globalThis.VNSites) return; // loaded twice (a worker that also lists it): keep one

  const api = globalThis.browser ?? globalThis.chrome;

  const VISIO = { id: 'visio', origins: ['https://visio.numerique.gouv.fr/*'], js: ['providers/visio.js', 'call-bridge.js'] };
  /** Opt-in sites; their origins together are the manifest's optional_host_permissions. */
  const OPTIONAL = [
    { id: 'meet', origins: ['https://meet.google.com/*'], js: ['providers/meet.js', 'call-bridge.js'] },
    {
      id: 'teams',
      // All three: permissions are all-or-nothing on the array.
      origins: ['https://teams.microsoft.com/*', 'https://teams.cloud.microsoft/*', 'https://teams.live.com/*'],
      js: ['providers/teams.js', 'call-bridge.js'],
    },
  ];

  async function allowed(site) {
    try {
      return await api.permissions.contains({ origins: site.origins });
    } catch (e) {
      return false;
    }
  }

  /** Visio plus every opted-in site. */
  async function activeSites() {
    const sites = [VISIO];
    for (const site of OPTIONAL) if (await allowed(site)) sites.push(site);
    return sites;
  }

  /** Ids of the tabs open on any of these origins (one query per origin: robust across browsers). */
  async function tabIdsFor(origins) {
    const ids = new Set();
    for (const origin of origins) {
      try {
        for (const tab of await api.tabs.query({ url: origin })) ids.add(tab.id);
      } catch (e) { /* bad pattern for this browser: skip it */ }
    }
    return ids;
  }

  /** Start the call bridge in a site's open tabs (call-bridge.js runs once per page). */
  async function inject(site) {
    if (!api.scripting) return;
    try {
      for (const id of await tabIdsFor(site.origins)) {
        Promise.resolve(api.scripting.executeScript({ target: { tabId: id }, files: site.js })).catch(() => {});
      }
    } catch (e) { /* query failed */ }
  }

  /**
   * Records in storage.local.unavailable (site ids) the allowed sites this browser
   * refused to register, for the options page to say so next to their switch.
   */
  async function setUnavailable(siteId, unavailable) {
    if (!api.storage || !api.storage.local) return;
    try {
      const list = (await api.storage.local.get('unavailable')).unavailable || [];
      if (list.includes(siteId) === unavailable) return;
      const next = unavailable ? [...list, siteId] : list.filter((id) => id !== siteId);
      await api.storage.local.set({ unavailable: next });
    } catch (e) { /* storage unavailable: the note just won't show */ }
  }

  /** Register the content scripts of opted-in sites, unregister the others. */
  async function doSync() {
    if (!api.scripting || !api.scripting.registerContentScripts) return;
    for (const site of OPTIONAL) {
      const id = 'vn-' + site.id;
      let failed = false;
      try {
        const registered = (await api.scripting.getRegisteredContentScripts()).some((s) => s.id === id);
        const on = await allowed(site);
        if (on && !registered) {
          try {
            await api.scripting.registerContentScripts([{
              id, matches: site.origins, js: site.js, runAt: 'document_idle', persistAcrossSessions: true,
            }]);
          } catch (e) {
            failed = true; // allowed, but this browser can't register scripts there
            console.warn('VisioNext: could not register the ' + site.id + ' script', e);
          }
          if (!failed) await inject(site).catch(() => {}); // tabs opened before the permission was granted
        } else if (!on && registered) {
          await api.scripting.unregisterContentScripts({ ids: [id] });
        }
      } catch (e) { /* this browser can't list or unregister scripts: leave it */ }
      await setUnavailable(site.id, failed); // only an allowed site can fail
    }
  }

  /** Drop our registrations so the next sync registers this version's js/matches. */
  async function dropRegistrations() {
    try {
      if (api.scripting && api.scripting.getRegisteredContentScripts) {
        const ids = (await api.scripting.getRegisteredContentScripts()).map((s) => s.id).filter((id) => id.startsWith('vn-'));
        if (ids.length) await api.scripting.unregisterContentScripts({ ids });
      }
    } catch (e) { /* nothing to clean */ }
  }

  // Serialized: overlapping permission events / startups must not interleave.
  let syncing = Promise.resolve();
  function sync() { return (syncing = syncing.then(doSync, doSync)); }
  /** Re-register from scratch (install, update): drop, then sync, through the same chain. */
  function resync() {
    syncing = syncing.then(dropRegistrations, dropRegistrations);
    return sync();
  }

  /**
   * Stop the call bridges already running on sites the user just revoked: unregistering
   * only spares new pages. Revoking any of a site's origins stops the whole site. Every
   * tab gets it (each bridge checks its own URL): once access is gone, a `url` query no
   * longer sees those tabs.
   */
  async function stopRevoked(removedOrigins) {
    const removed = removedOrigins || [];
    const origins = OPTIONAL.filter((s) => s.origins.some((o) => removed.includes(o))).flatMap((s) => s.origins);
    if (!origins.length) return;
    try {
      for (const tab of await api.tabs.query({})) {
        Promise.resolve(api.tabs.sendMessage(tab.id, { type: 'stop', origins })).catch(() => {});
      }
    } catch (e) { /* query failed */ }
  }

  globalThis.VNSites = {
    VISIO, OPTIONAL, allowed, activeSites, tabIdsFor, inject, sync, resync, stopRevoked,
  };
})();
