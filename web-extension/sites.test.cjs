// The sites are described in three places that must agree: manifest.json (host
// permissions, the static content script), sites.js (VISIO, OPTIONAL: what gets
// registered and injected, and the options switches) and providers/*.js (which hosts
// each adapter claims). Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');

const MANIFEST = JSON.parse(fs.readFileSync(__dirname + '/manifest.json', 'utf8'));

const read = (file) => fs.readFileSync(__dirname + '/' + file, 'utf8');

/** VISIO and OPTIONAL as sites.js defines them (run in a vm). */
function siteLists() {
  const ctx = {};
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(read('sites.js'), ctx);
  // Plain copies: deepEqual checks prototypes, and the vm has its own Array/Object.
  return JSON.parse(vm.runInContext('JSON.stringify({ visio: VNSites.VISIO, optional: VNSites.OPTIONAL })', ctx));
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
      permissions: { request() {}, contains(q) { asked.push(q.origins); return new Promise(() => {}); } },
      scripting: { registerContentScripts() {} },
    },
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(read('sites.js'), ctx); // as options.html loads them
  vm.runInContext(read('options.js'), ctx);
  // One question per switch, in page order.
  return JSON.parse(JSON.stringify(Object.fromEntries(boxes.map((box, k) => [box.dataset.site, asked[k]]))));
}

const { visio: VISIO, optional: OPTIONAL } = siteLists();
const SITES = [VISIO, ...OPTIONAL];
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
      // Nor lookalikes: a parent domain, a subdomain, a suffix.
      const host = hostOf(origin);
      for (const other of [host.split('.').slice(1).join('.'), 'x.' + host, host + '.evil.test']) {
        assert.deepEqual(providers.filter((p) => p.matches(other)).map((p) => p.id), [], other);
      }
    }
  });
});

test('sites: the options switches ask for the same origins as the background registers', () => {
  const asked = optionsOrigins();
  assert.deepEqual(Object.keys(asked), OPTIONAL.map((s) => s.id));
  for (const site of OPTIONAL) assert.deepEqual(asked[site.id], site.origins, site.id);
});

test('sites: every origin is a literal https://<host>/* (call-bridge.js compares hosts exactly)', () => {
  for (const origin of SITES.flatMap((s) => s.origins)) {
    assert.match(origin, /^https:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+\/\*$/, origin);
  }
});

test('sites: sites.js is loaded before what uses it, everywhere it ships', () => {
  assert.deepEqual(MANIFEST.background.scripts, ['sites.js', 'background.js']); // Firefox
  assert.match(read('background.js'), /importScripts\('sites\.js'\)/); // service workers
  assert.match(read('options.html'), /<script src="sites\.js"><\/script>\s*<script src="options\.js">/);
  assert.match(read('package.mjs'), /'sites\.js'/);
});
