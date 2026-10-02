// Background tests: background.js (and the sites.js it imports) run in a vm with a
// fake browser API (native port, tabs, permissions, scripting, storage) that records
// what it is asked to do. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');

const SRC = fs.readFileSync(__dirname + '/background.js', 'utf8');
const read = (file) => fs.readFileSync(__dirname + '/' + file, 'utf8');
const VISIO = 'https://visio.numerique.gouv.fr/*';
const MEET = 'https://meet.google.com/*';
const TEAMS = 'https://teams.microsoft.com/*';
const TEAMS_ALL = [TEAMS, 'https://teams.cloud.microsoft/*', 'https://teams.live.com/*'];

/** A copy made of this realm's objects (the vm has its own Object/Array). */
const plain = (v) => JSON.parse(JSON.stringify(v));
/** Lets the background's promise chains run. */
const settle = () => new Promise((r) => setTimeout(r, 5));

function event() {
  const listeners = [];
  return { addListener: (fn) => listeners.push(fn), fire: (...args) => listeners.forEach((fn) => fn(...args)) };
}

/**
 * tabs: { origin pattern: [tab ids] }; granted: optional origins allowed;
 * registered: content scripts already registered; refuse: ids registration throws for;
 * stored: storage.local's initial content.
 */
async function setup({ tabs = {}, granted = [], registered = [], refuse = [], stored = {} } = {}) {
  const ports = [], sent = [], log = [];
  const allowed = new Set(granted);
  const storage = plain(stored);
  const chrome = {
    runtime: {
      onMessage: event(), onStartup: event(), onInstalled: event(),
      connectNative() {
        const port = {
          msgs: [], closed: false, broken: false, onMessage: event(), onDisconnect: event(),
          postMessage(m) { if (port.broken) throw new Error('disconnected'); port.msgs.push(plain(m)); },
          disconnect() { port.closed = true; },
        };
        ports.push(port);
        return port;
      },
    },
    tabs: {
      onRemoved: event(),
      async query({ url }) {
        const ids = url ? tabs[url] || [] : [...new Set(Object.values(tabs).flat())];
        return ids.map((id) => ({ id }));
      },
      async sendMessage(id, msg) { sent.push([id, plain(msg)]); },
    },
    permissions: {
      onAdded: event(), onRemoved: event(),
      async contains({ origins }) { return origins.every((o) => allowed.has(o)); },
    },
    scripting: {
      async executeScript({ target, files }) { log.push(['inject', target.tabId, files.join(' ')]); },
      async registerContentScripts(list) {
        if (list.some((s) => refuse.includes(s.id))) throw new Error('refused');
        for (const s of list) { registered.push(plain(s)); log.push(['register', s.id]); }
      },
      async unregisterContentScripts({ ids }) {
        for (const id of ids) registered.splice(registered.findIndex((s) => s.id === id), 1);
        log.push(['unregister', ...ids]);
      },
      async getRegisteredContentScripts() { return registered.slice(); },
    },
    storage: {
      local: {
        async get(key) { return plain({ [key]: storage[key] }); },
        async set(items) { Object.assign(storage, plain(items)); },
      },
    },
  };
  // A service worker: background.js imports sites.js itself.
  const ctx = { chrome, console: { warn() {} } };
  ctx.globalThis = ctx;
  ctx.importScripts = (file) => vm.runInContext(read(file), ctx);
  vm.createContext(ctx);
  vm.runInContext(SRC, ctx);
  await settle();
  return {
    chrome, ports, sent, log, registered, allowed, storage,
    fromTab(id, msg) { chrome.runtime.onMessage.fire(msg, { tab: { id } }); },
    async fromApp(msg, port = ports.at(-1)) { port.onMessage.fire(msg); await settle(); },
    ids(registered) { return registered.map((s) => s.id).sort(); },
  };
}

const LIVE = { type: 'state', muted: false, canUnmute: true };

test('background: relays a tab report to the app with its tab id', async () => {
  const h = await setup();
  h.fromTab(9, LIVE);
  h.chrome.runtime.onMessage.fire(LIVE, {}); // not from a tab
  h.fromTab(9, { type: 'other' });
  assert.equal(h.ports.length, 1);
  assert.deepEqual(h.ports[0].msgs, [{ ...LIVE, tabId: 9 }]);
});

test('background: the last bye is relayed, then the port is closed', async () => {
  const h = await setup();
  h.fromTab(1, LIVE); h.fromTab(2, LIVE);
  h.fromTab(1, { type: 'bye' });
  assert.equal(h.ports[0].closed, false);
  h.chrome.tabs.onRemoved.fire(2); // a closed tab says bye for its call
  assert.deepEqual(h.ports[0].msgs.at(-1), { type: 'bye', tabId: 2 });
  assert.equal(h.ports[0].closed, true);
  h.fromTab(3, LIVE);
  assert.equal(h.ports.length, 2);
});

test('background: a report after the app went away reconnects', async () => {
  const h = await setup();
  h.fromTab(1, LIVE);
  h.ports[0].onDisconnect.fire();
  h.fromTab(1, { ...LIVE, muted: true });
  assert.equal(h.ports.length, 2);
  assert.deepEqual(h.ports[1].msgs, [{ ...LIVE, muted: true, tabId: 1 }]);
});

test("background: a late disconnect from a replaced port doesn't drop the new one", async () => {
  const h = await setup();
  h.fromTab(1, LIVE);
  const old = h.ports[0];
  old.broken = true;
  h.fromTab(1, LIVE); // fails: dropped
  h.fromTab(1, LIVE); // new port
  old.onDisconnect.fire(); // the old port's event arrives late
  h.fromTab(1, LIVE);
  assert.equal(h.ports.length, 2);
  assert.equal(h.ports[1].msgs.length, 2);
});

test('background: a bye for an unknown call opens no port', async () => {
  const h = await setup();
  h.fromTab(3, { type: 'bye' });
  h.chrome.tabs.onRemoved.fire(4);
  assert.equal(h.ports.length, 0);
});

test("background: unwraps Safari's { name, userInfo } messages", async () => {
  const h = await setup({ tabs: { [VISIO]: [7] } });
  h.fromTab(9, LIVE);
  await h.fromApp({ name: 'setMuted', userInfo: { type: 'setMuted', value: false, tabId: 9 } });
  assert.deepEqual(h.sent, [[9, { type: 'setMuted', value: false }]]);
});

test('background: a mute goes once to every call-site tab and known call', async () => {
  const h = await setup({ tabs: { [VISIO]: [7, 9], [MEET]: [5], [TEAMS]: [6] }, granted: [MEET] });
  h.fromTab(9, LIVE); h.fromTab(11, LIVE); // 11: on a site revoked mid-call
  await h.fromApp({ type: 'setMuted', value: true });
  assert.deepEqual(h.sent.map(([id]) => id).sort((a, b) => a - b), [5, 7, 9, 11]);
  assert.ok(h.sent.every(([, msg]) => msg.type === 'setMuted' && msg.value === true));
});

test('background: an unmute goes to its one tab only', async () => {
  const h = await setup({ tabs: { [VISIO]: [7, 9] } });
  h.fromTab(9, LIVE); h.fromTab(7, LIVE);
  await h.fromApp({ type: 'setMuted', value: false, tabId: 9 });
  await h.fromApp({ type: 'other', value: true });
  assert.deepEqual(h.sent, [[9, { type: 'setMuted', value: false }]]);
});

test('background: registers allowed sites and unregisters revoked ones', async () => {
  const h = await setup({ tabs: { [MEET]: [5], 'https://teams.live.com/*': [6] }, granted: [MEET] });
  assert.deepEqual(h.ids(h.registered), ['vn-meet']);
  assert.deepEqual(h.registered[0].matches, [MEET]);
  assert.deepEqual(h.registered[0].js, ['providers/meet.js', 'call-bridge.js']);
  assert.deepEqual(h.log.filter(([what]) => what === 'inject'), [['inject', 5, 'providers/meet.js call-bridge.js']]);

  TEAMS_ALL.forEach((o) => h.allowed.add(o));
  h.chrome.permissions.onAdded.fire({ origins: TEAMS_ALL });
  await settle();
  assert.deepEqual(h.ids(h.registered), ['vn-meet', 'vn-teams']);
  assert.deepEqual(h.log.at(-1), ['inject', 6, 'providers/teams.js call-bridge.js']);

  h.allowed.delete(MEET);
  h.chrome.permissions.onRemoved.fire({ origins: [MEET] });
  await settle();
  assert.deepEqual(h.ids(h.registered), ['vn-teams']);
});

test('background: an update re-registers from scratch and injects each open call tab once', async () => {
  const registered = [{ id: 'vn-meet', js: ['old.js'] }, { id: 'someone-else' }];
  const h = await setup({ tabs: { [VISIO]: [7], [MEET]: [5] }, granted: [MEET], registered });
  assert.deepEqual(h.log, []); // already registered at startup
  h.chrome.runtime.onInstalled.fire({ reason: 'update' });
  await settle();
  assert.deepEqual(h.log, [
    ['unregister', 'vn-meet'],
    ['register', 'vn-meet'],
    ['inject', 5, 'providers/meet.js call-bridge.js'],
    ['inject', 7, 'providers/visio.js call-bridge.js'],
  ]);
  assert.deepEqual(h.ids(registered), ['someone-else', 'vn-meet']);
  assert.deepEqual(registered.find((s) => s.id === 'vn-meet').js, ['providers/meet.js', 'call-bridge.js']);
});

test('background: a browser update keeps the registrations and injects nothing', async () => {
  const h = await setup({ tabs: { [VISIO]: [7], [MEET]: [5] }, granted: [MEET], registered: [{ id: 'vn-meet' }] });
  h.chrome.runtime.onInstalled.fire({ reason: 'browser_update' });
  await settle();
  assert.deepEqual(h.log, []);
});

test('background: records the allowed sites this browser refuses to register', async () => {
  const h = await setup({
    tabs: { [MEET]: [5] }, granted: [MEET, ...TEAMS_ALL], refuse: ['vn-meet'], stored: { unavailable: ['teams'] },
  });
  assert.deepEqual(h.storage.unavailable, ['meet']); // teams registered: no longer listed
  assert.deepEqual(h.ids(h.registered), ['vn-teams']);
  assert.deepEqual(h.log.filter(([what]) => what === 'inject'), []); // nothing runs on a refused site
  h.allowed.delete(MEET);
  h.chrome.permissions.onRemoved.fire({ origins: [MEET] });
  await settle();
  assert.deepEqual(h.storage.unavailable, []);
});

test("background: a revoked site's tabs are told to stop", async () => {
  const h = await setup({ tabs: { [VISIO]: [7], [MEET]: [5] }, granted: [MEET] });
  h.allowed.delete(MEET);
  h.chrome.permissions.onRemoved.fire({ origins: [MEET] });
  await settle();
  const stops = h.sent.filter(([, msg]) => msg.type === 'stop');
  // Every tab hears it (a revoked origin's tabs can't be queried); each checks its URL.
  assert.deepEqual(stops.map(([id]) => id).sort(), [5, 7]);
  assert.ok(stops.every(([, msg]) => msg.origins.length === 1 && msg.origins[0] === MEET));
});

test('background: revoking one origin of a site stops the whole site', async () => {
  const h = await setup({ tabs: { [TEAMS]: [6] }, granted: TEAMS_ALL });
  h.allowed.delete(TEAMS_ALL[2]);
  h.chrome.permissions.onRemoved.fire({ origins: [TEAMS_ALL[2]] });
  await settle();
  assert.deepEqual(h.sent, [[6, { type: 'stop', origins: TEAMS_ALL }]]);
});

test('background: a revoked origin of no opt-in site stops nothing', async () => {
  const h = await setup({ tabs: { [VISIO]: [7] } });
  h.chrome.permissions.onRemoved.fire({ origins: [VISIO] });
  h.chrome.permissions.onRemoved.fire({});
  await settle();
  assert.deepEqual(h.sent, []);
});
