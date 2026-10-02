// Options page tests: sites.js + options.js run in a vm with a fake page and browser
// API. Run: node --test
const { test } = require('node:test');
const assert = require('node:assert');
const vm = require('node:vm');
const fs = require('node:fs');

const read = (file) => fs.readFileSync(__dirname + '/' + file, 'utf8');
const flush = () => new Promise((r) => setImmediate(r));

/**
 * contains/request: the permissions answers; unavailable: storage.local's list;
 * sites: replaces sites.js's VNSites.OPTIONAL (undefined: load sites.js).
 */
function setup({ contains, request = async () => true, unavailable, sites }) {
  const boxes = ['meet', 'teams'].map((site) => {
    const note = { hidden: true };
    return {
      dataset: { site }, checked: false, disabled: false, note, on: {},
      parentNode: { querySelector: () => note },
      addEventListener(type, fn) { this.on[type] = fn; },
    };
  });
  const section = { hidden: false, querySelectorAll: () => boxes };
  const asked = [], changed = [];
  const ctx = {
    document: { getElementById: (id) => (id === 'sites' ? section : { hidden: true }) },
    console: { warn() {} },
    Promise,
    chrome: {
      permissions: {
        contains: (q) => { asked.push(q.origins); return contains(q); },
        request, remove: async () => true,
      },
      scripting: { registerContentScripts() {} },
      storage: {
        local: { get: async () => (unavailable ? { unavailable } : {}) },
        onChanged: { addListener: (fn) => changed.push(fn) },
      },
    },
  };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  if (sites) ctx.VNSites = { OPTIONAL: sites };
  else vm.runInContext(read('sites.js'), ctx);
  vm.runInContext(read('options.js'), ctx);
  return {
    boxes, asked,
    notes: () => boxes.map((b) => !b.note.hidden),
    async flip(box) { box.checked = !box.checked; box.on.change(); await flush(); },
    async store(list, area = 'local') { changed.forEach((fn) => fn({ unavailable: { newValue: list } }, area)); await flush(); },
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

test('options: a failed permission check re-enables the switch', async () => {
  const h = setup({ contains: async () => { throw new Error('no'); } });
  await flush();
  assert.deepEqual(h.boxes.map((b) => [b.checked, b.disabled]), [[false, false], [false, false]]);
});

test('options: a switch without origins stays disabled and asks nothing', async () => {
  const h = setup({ contains: async () => true, sites: [{ id: 'meet', origins: ['https://meet.google.com/*'] }] });
  await flush();
  assert.deepEqual(h.boxes.map((b) => b.disabled), [false, true]);
  assert.deepEqual(JSON.parse(JSON.stringify(h.asked)), [['https://meet.google.com/*']]);
});

test('options: an allowed site the background could not register says so', async () => {
  const h = setup({ contains: async () => true, unavailable: ['teams'] });
  await flush();
  assert.deepEqual(h.notes(), [false, true]);
});

test('options: the note follows what the background records', async () => {
  const h = setup({ contains: async () => false });
  await flush();
  const [meet] = h.boxes;
  await h.flip(meet);
  assert.deepEqual(h.notes(), [false, false]);
  await h.store(['meet', 'teams']); // teams is off: no note
  assert.deepEqual(h.notes(), [true, false]);
  await h.store(['teams'], 'sync'); // another area: ignored
  assert.deepEqual(h.notes(), [true, false]);
  await h.store([]);
  assert.deepEqual(h.notes(), [false, false]);
});

test('options: turning a switch off never shows the note', async () => {
  const h = setup({ contains: async () => true, unavailable: ['meet'] });
  await flush();
  assert.deepEqual(h.notes(), [true, false]);
  await h.flip(h.boxes[0]);
  assert.deepEqual(h.notes(), [false, false]);
  await h.store(['meet']); // the background hasn't caught up yet
  assert.deepEqual(h.notes(), [false, false]);
});

test('options: a refused grant puts the switch back, without a note', async () => {
  const h = setup({ contains: async () => false, request: async () => false, unavailable: ['meet'] });
  await flush();
  await h.flip(h.boxes[0]);
  assert.equal(h.boxes[0].checked, false);
  assert.deepEqual(h.notes(), [false, false]);
});
