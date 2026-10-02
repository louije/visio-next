// Core tests: call-bridge.js run in a vm with stubbed timers/observer/runtime and a
// fake provider, independent of the real adapters. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');

const SRC = fs.readFileSync(__dirname + '/call-bridge.js', 'utf8');

function setup(opts, shared) {
  opts = opts || {};
  // canToggle false: the provider finds nothing to press (toggle() returns false).
  const page = { state: { muted: false, canUnmute: true }, clicks: 0, tries: 0, reflect: true, canToggle: true };
  const provider = {
    id: 'fake',
    guardToggle: opts.guardToggle !== false,
    matches: () => true,
    read: () => (page.state ? Object.assign({}, page.state) : null),
    toggle: () => {
      page.tries++;
      if (!page.canToggle) return false;
      page.clicks++;
      if (page.reflect && page.state) page.state = Object.assign({}, page.state, { muted: !page.state.muted });
      return true;
    },
  };
  let now = 0, id = 0, moCb = null, runtimeId = 'x';
  const timers = [], sent = [], listeners = [], windowListeners = {};
  const add = (fn, ms, every) => { const t = { id: ++id, fn, at: now + ms, every }; timers.push(t); return t.id; };
  const clear = (i) => { const k = timers.findIndex((t) => t.id === i); if (k >= 0) timers.splice(k, 1); };
  const ctx = {
    document: { documentElement: {} },
    location: { host: 'x.test', href: 'https://x.test/room' },
    window: { addEventListener: (type, fn) => { windowListeners[type] = fn; } },
    console: { warn() {} },
    MutationObserver: function (cb) { moCb = cb; this.observe = () => {}; this.disconnect = () => {}; },
    setTimeout: (f, ms) => add(f, ms), setInterval: (f, ms) => add(f, ms, ms),
    clearTimeout: clear, clearInterval: clear,
    chrome: { runtime: {
      get id() { return runtimeId; },
      sendMessage: (m) => { sent.push(Object.assign({ t: now }, m)); },
      onMessage: { addListener: (l) => listeners.push(l) },
    } },
  };
  ctx.globalThis = ctx;
  if (shared) ctx.__vnCallBridge = shared;
  ctx.__vnProviders = [provider];
  vm.createContext(ctx);
  vm.runInContext(SRC, ctx);
  return {
    ctx, page, sent, timers,
    advance(ms) {
      const end = now + ms;
      for (;;) {
        timers.sort((a, b) => a.at - b.at);
        const t = timers[0];
        if (!t || t.at > end) break;
        now = t.at;
        if (t.every) t.at += t.every; else timers.shift();
        t.fn();
      }
      now = end;
    },
    mutate() { if (moCb) moCb([]); },
    fire(type) { windowListeners[type](); },
    unload() { runtimeId = undefined; }, // the extension was reloaded or updated
    message(msg) { listeners.forEach((l) => l(msg)); },
    press(value) { listeners.forEach((l) => l({ type: 'setMuted', value })); },
    states() { return sent.filter((m) => m.type === 'state'); },
  };
}

test('core: reports a state once, and again only on change', () => {
  const h = setup();
  h.advance(300);
  h.mutate(); h.advance(300);
  assert.equal(h.states().length, 1);
  h.page.state = { muted: true, canUnmute: true };
  h.mutate(); h.advance(300);
  assert.deepEqual(h.states().map((m) => m.muted), [false, true]);
});

test('core: says bye after the 2 s grace, not if the call comes back', () => {
  const h = setup();
  h.advance(300);
  h.page.state = null; h.mutate(); h.advance(1900);
  h.page.state = { muted: false, canUnmute: true }; h.mutate(); h.advance(1000);
  assert.equal(h.sent.filter((m) => m.type === 'bye').length, 0);
  h.page.state = null; h.mutate(); h.advance(3000);
  assert.equal(h.sent.filter((m) => m.type === 'bye').length, 1);
});

test('core: the heartbeat re-reads the page', () => {
  const h = setup();
  h.advance(300);
  h.page.state = { muted: true, canUnmute: true }; // no mutation
  h.advance(30000);
  assert.equal(h.states().at(-1).muted, true);
});

test('core: a page that reflects slowly does not disable pressing', () => {
  const h = setup();
  h.advance(300);
  h.page.reflect = false;
  h.press(true);
  h.advance(1100); // verify ran, state still wrong
  h.page.state = { muted: true, canUnmute: true }; // reflects at ~1.2 s
  h.mutate(); h.advance(3000);
  h.page.state = { muted: false, canUnmute: true }; h.mutate(); h.advance(300);
  h.press(true);
  assert.equal(h.page.clicks, 2);
});

test('core: a press that never takes stops pressing on that page', () => {
  const h = setup();
  h.advance(300);
  h.page.reflect = false;
  h.press(true);
  h.advance(4000);
  h.press(true);
  assert.equal(h.page.clicks, 1);
});

test('core: a provider without guardToggle keeps pressing', () => {
  const h = setup({ guardToggle: false });
  h.advance(300);
  h.page.reflect = false;
  h.press(true);
  h.advance(4000);
  h.press(true);
  assert.equal(h.page.clicks, 2);
});

test('core: an unreadable state is retried after 1 s', () => {
  const h = setup();
  h.advance(300);
  h.page.state = { muted: null, canUnmute: true };
  h.mutate(); h.advance(300);
  h.page.state = { muted: true, canUnmute: true }; // no mutation follows
  h.advance(1500);
  assert.equal(h.states().at(-1).muted, true);
});

test('core: a live instance makes a second injection return', () => {
  let stopped = false;
  const h = setup({}, { alive: () => true, stop: () => { stopped = true; } });
  h.advance(300);
  assert.equal(stopped, false);
  assert.equal(h.sent.length, 0);
});

test('core: an orphan is stopped and the new instance runs', () => {
  let stopped = false;
  const h = setup({}, { alive: () => false, stop: () => { stopped = true; } });
  h.advance(300);
  assert.equal(stopped, true);
  assert.equal(h.states().length, 1);
  assert.equal(typeof h.ctx.__vnCallBridge.alive, 'function');
});

test('core: an old-style boolean marker is treated as an orphan with nothing to stop', () => {
  const h = setup({}, true);
  h.advance(300);
  assert.equal(h.states().length, 1);
});

test('core: a press that never took is forgotten once the call ends', () => {
  const h = setup();
  h.advance(300);
  h.page.reflect = false;
  h.press(true);
  h.advance(4000); // gave up on this call's controls
  h.page.state = null; h.mutate(); h.advance(3000); // left the call
  h.page.reflect = true;
  h.page.state = { muted: false, canUnmute: true }; h.mutate(); h.advance(300); // a new one
  h.press(true);
  assert.equal(h.page.clicks, 2);
});

test('core: a stop for this site says bye, then nothing more', () => {
  const h = setup();
  h.advance(300);
  h.message({ type: 'stop', origins: ['https://x.test/*'] });
  assert.deepEqual(h.sent.map((m) => m.type), ['state', 'bye']);
  assert.equal(h.ctx.__vnCallBridge, undefined);
  h.page.state = { muted: true, canUnmute: true }; h.mutate(); h.advance(60000);
  h.press(false);
  assert.equal(h.sent.length, 2);
  assert.equal(h.page.clicks, 0);
});

test('core: a stop for other sites is ignored', () => {
  const h = setup();
  h.advance(300);
  h.message({ type: 'stop', origins: ['https://y.test/*', 'https://x.test.evil/*'] });
  h.page.state = { muted: true, canUnmute: true }; h.mutate(); h.advance(300);
  assert.deepEqual(h.states().map((m) => m.muted), [false, true]);
});

test('core: leaving the page says bye', () => {
  const h = setup();
  h.advance(300);
  h.fire('pagehide');
  assert.deepEqual(h.sent.map((m) => m.type), ['state', 'bye']);
});

test('core: once the extension is gone, it tears down and sends nothing', () => {
  const h = setup();
  h.advance(300);
  h.unload();
  h.page.state = { muted: true, canUnmute: true }; h.mutate(); h.advance(60000);
  assert.equal(h.sent.length, 1);
  assert.equal(h.ctx.__vnCallBridge, undefined);
  assert.equal(h.timers.length, 0);
});

test('core: no state follows a bye, heartbeat or not', () => {
  const h = setup();
  h.advance(300);
  h.page.state = null; h.mutate(); h.advance(3000);
  h.advance(60000);
  assert.deepEqual(h.sent.map((m) => m.type), ['state', 'bye']);
});

test('core: a press with nothing to press is not left pending', () => {
  const h = setup();
  h.advance(300);
  h.page.canToggle = false;
  h.press(true);
  h.page.canToggle = true;
  h.press(true);
  assert.equal(h.page.tries, 2);
  assert.equal(h.page.clicks, 1);
});

test('core: rejoining reports the call again, with one heartbeat', () => {
  const h = setup();
  h.advance(300);
  h.page.state = null; h.mutate(); h.advance(3000);
  h.page.state = { muted: false, canUnmute: true }; h.mutate(); h.advance(300); // same state as before
  h.advance(30000);
  const after = h.sent.slice(h.sent.findIndex((m) => m.type === 'bye') + 1);
  assert.deepEqual(after.map((m) => m.type), ['state', 'state']); // the report, one beat
});

test('core: a slow press that took is not blamed for a later manual change', () => {
  const h = setup();
  h.advance(300);
  h.page.reflect = false;
  h.press(true);
  h.advance(1100); // verify ran, state still wrong
  h.page.state = { muted: true, canUnmute: true }; h.mutate(); h.advance(300); // took at ~1.2 s
  h.page.state = { muted: false, canUnmute: true }; h.mutate(); h.advance(3000); // the user unmutes
  h.page.reflect = true;
  h.press(true);
  assert.equal(h.page.clicks, 2);
});
