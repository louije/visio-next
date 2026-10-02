// Options page tests: options.js run in a vm with a fake page and browser API.
// Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');

const SRC = fs.readFileSync(__dirname + '/options.js', 'utf8');
const MANIFEST = JSON.parse(fs.readFileSync(__dirname + '/manifest.json', 'utf8'));
const flush = () => new Promise((r) => setImmediate(r));

function setup({ contains, request = async () => true, registered = [] }) {
  const timers = [];
  const boxes = ['meet', 'teams'].map((site) => {
    const note = { hidden: true };
    return {
      dataset: { site }, checked: false, disabled: false, note, on: {},
      parentNode: { querySelector: () => note },
      addEventListener(type, fn) { this.on[type] = fn; },
    };
  });
  const section = { hidden: false, querySelectorAll: () => boxes };
  const asked = [];
  const ctx = {
    document: { getElementById: (id) => (id === 'sites' ? section : { hidden: true }) },
    console: { warn() {} },
    setTimeout: (fn, ms) => timers.push({ fn, ms }),
    Promise,
    chrome: {
      runtime: { getManifest: () => MANIFEST },
      permissions: {
        contains: (q) => { asked.push(q.origins); return contains(q); },
        request, remove: async () => true,
      },
      scripting: { registerContentScripts() {}, getRegisteredContentScripts: async () => registered },
    },
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(SRC, ctx);
  return {
    boxes, asked,
    async runTimers() { while (timers.length) timers.shift().fn(); await flush(); },
    async flip(box) { box.checked = !box.checked; box.on.change(); await flush(); },
  };
}

test('options: a switch is disabled until its state is known', async () => {
  const answers = [];
  const h = setup({ contains: () => new Promise((r) => answers.push(r)) });
  assert.deepEqual(h.boxes.map((b) => b.disabled), [true, true]);
  answers[0](true); await flush();
  assert.equal(h.boxes[0].checked, true);
  assert.deepEqual(h.boxes.map((b) => b.disabled), [false, true]);
});

test('options: a granted site whose script did not register says so', async () => {
  const h = setup({ contains: async () => false, registered: [{ id: 'vn-teams' }] });
  await flush();
  const [meet, teams] = h.boxes;
  await h.flip(meet); await h.flip(teams);
  await h.runTimers();
  assert.equal(meet.checked, true); // left as granted
  assert.equal(meet.note.hidden, false);
  assert.equal(teams.note.hidden, true);
  await h.flip(meet);
  assert.equal(meet.note.hidden, true);
});

test('options: a refused grant puts the switch back', async () => {
  const h = setup({ contains: async () => false, request: async () => false });
  await flush();
  await h.flip(h.boxes[0]);
  await h.runTimers();
  assert.equal(h.boxes[0].checked, false);
  assert.equal(h.boxes[0].note.hidden, true);
});
