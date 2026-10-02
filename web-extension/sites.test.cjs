// The sites are described in three places that must agree: manifest.json (host
// permissions, the static content script), background.js (VISIO, OPTIONAL: what gets
// registered and injected) and providers/*.js (which hosts each adapter claims).
// options.js builds its switches from the manifest. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');

const MANIFEST = JSON.parse(fs.readFileSync(__dirname + '/manifest.json', 'utf8'));

/** VISIO and OPTIONAL as background.js defines them (run in a vm with a stub API). */
function backgroundSites() {
  const ev = () => ({ addListener() {} });
  const chrome = {
    runtime: { onMessage: ev(), onStartup: ev(), onInstalled: ev() },
    tabs: { onRemoved: ev() },
    permissions: { onAdded: ev(), onRemoved: ev() },
  };
  const ctx = { chrome, console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(__dirname + '/background.js', 'utf8'), ctx);
  // Plain copies: deepEqual checks prototypes, and the vm has its own Array/Object.
  return JSON.parse(vm.runInContext('JSON.stringify({ visio: VISIO, optional: OPTIONAL })', ctx));
}

/** The origins options.js asks about for each switch, by site. */
function optionsOrigins() {
  const asked = [];
  const boxes = ['meet', 'teams'].map((site) => ({
    dataset: { site }, addEventListener() {}, parentNode: { querySelector: () => ({}) },
  }));
  const ctx = {
    document: { getElementById: () => ({ querySelectorAll: () => boxes }) },
    Promise,
    chrome: {
      runtime: { getManifest: () => MANIFEST },
      permissions: { request() {}, contains(q) { asked.push(q.origins); return new Promise(() => {}); } },
      scripting: { registerContentScripts() {} },
    },
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(__dirname + '/options.js', 'utf8'), ctx);
  // One question per switch, in page order.
  return JSON.parse(JSON.stringify(Object.fromEntries(boxes.map((box, k) => [box.dataset.site, asked[k]]))));
}

const { visio: VISIO, optional: OPTIONAL } = backgroundSites();
const SITES = [Object.assign({ id: 'visio' }, VISIO), ...OPTIONAL];
const sorted = (list) => list.slice().sort();
const hostOf = (origin) => new URL(origin.replace(/\*$/, '')).host;

test('sites: the opt-in origins are exactly the optional host permissions', () => {
  assert.deepEqual(sorted(OPTIONAL.flatMap((s) => s.origins)), sorted(MANIFEST.optional_host_permissions));
});

test('sites: Visio is exactly the required host permission and the static content script', () => {
  assert.deepEqual(VISIO.origins, MANIFEST.host_permissions);
  assert.equal(MANIFEST.content_scripts.length, 1);
  const cs = MANIFEST.content_scripts[0];
  assert.deepEqual(cs.matches, VISIO.origins);
  assert.deepEqual(cs.js.slice(-2), ['providers/visio.js', 'call-bridge.js']);
  assert.deepEqual(cs.js, ['layout-engine.js', ...VISIO.js]);
});

test('sites: each site injects its provider, then the bridge', () => {
  for (const site of SITES) {
    assert.deepEqual(site.js, ['providers/' + site.id + '.js', 'call-bridge.js'], site.id);
    for (const file of site.js) assert.ok(fs.existsSync(__dirname + '/' + file), file);
  }
});

test("sites: each origin's host is claimed by its own provider only", () => {
  const providers = SITES.map((site) => require('./providers/' + site.id + '.js'));
  SITES.forEach((site, k) => {
    assert.equal(providers[k].id, site.id);
    for (const origin of site.origins) {
      const claimed = providers.filter((p) => p.matches(hostOf(origin))).map((p) => p.id);
      assert.deepEqual(claimed, [site.id], origin);
    }
  });
});

test('sites: the options switches ask for the same origins as the background registers', () => {
  const asked = optionsOrigins();
  assert.deepEqual(Object.keys(asked), OPTIONAL.map((s) => s.id));
  for (const site of OPTIONAL) assert.deepEqual(asked[site.id], site.origins, site.id);
});
