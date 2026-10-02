// Core tests: call-bridge.js run in a vm with stubbed timers/observer/runtime and a
// fake provider, independent of the real adapters. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');

const SRC = fs.readFileSync(__dirname + '/call-bridge.js', 'utf8');

function setup(opts, shared) {
  opts = opts || {};
  const page = { state: { muted: false, canUnmute: true }, clicks: 0, reflect: true };
  const provider = {
    id: 'fake',
    guardToggle: opts.guardToggle !== false,
    matches: () => true,
    read: () => (page.state ? Object.assign({}, page.state) : null),
    toggle: () => {
      page.clicks++;
      if (page.reflect && page.state) page.state = Object.assign({}, page.state, { muted: !page.state.muted });
      return true;
    },
  };
  let now = 0, id = 0, moCb = null, runtimeId = 'x';
  const timers = [], sent = [], listeners = [];
  const add = (fn, ms, every) => { const t = { id: ++id, fn, at: now + ms, every }; timers.push(t); return t.id; };
  const clear = (i) => { const k = timers.findIndex((t) => t.id === i); if (k >= 0) timers.splice(k, 1); };
  const ctx = {
    document: { documentElement: {} },
    location: { host: 'x.test', href: 'https://x.test/room' },
    window: { addEventListener() {} },
    console: { warn() {} },
    MutationObserver: function (cb) { moCb = cb; this.observe = () => {}; this.disconnect = () => {}; },
    setTimeout: (f, ms) => add(f, ms), setInterval: (f, ms) => add(f, ms, ms),
    clearTimeout: clear, clearInterval: clear,
    Date: { now: () => now },
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
