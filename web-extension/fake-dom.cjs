// Test helper: a tiny stand-in for the DOM the providers read. Elements have a tag,
// attributes, text, children, a `disabled` flag, a visibility flag and a click
// counter (a disabled element ignores clicks, as in a browser). Selectors are limited
// to what the providers use: tag, #id, .class, [attr], [attr="value"], alone or
// combined in that order.
'use strict';

const SELECTOR = /^([a-z]+)?(#[\w-]+)?(\.[\w-]+)?(?:\[([\w-]+)(?:="([^"]*)")?\])?$/;

function matches(e, sel) {
  const m = SELECTOR.exec(sel);
  if (!m) throw new Error('fake-dom: unsupported selector ' + sel);
  const [, tag, id, cls, attr, value] = m;
  if (tag && e.tag !== tag) return false;
  if (id && e.attrs.id !== id.slice(1)) return false;
  if (cls && !(e.attrs.class || '').split(' ').includes(cls.slice(1))) return false;
  // An attribute given as undefined is absent, as getAttribute says.
  if (attr && e.attrs[attr] === undefined) return false;
  if (value !== undefined && e.attrs[attr] !== value) return false;
  return true;
}

function descendants(node) {
  return node.children.flatMap((c) => [c, ...descendants(c)]);
}

function queryable(node) {
  node.querySelectorAll = (sel) => descendants(node).filter((e) => matches(e, sel));
  node.querySelector = (sel) => node.querySelectorAll(sel)[0] || null;
  return node;
}

/** el('button', { id: 'x' }, [children], { text, disabled, hidden }) */
function el(tag, attrs = {}, children = [], opts = {}) {
  return queryable({
    tag,
    attrs,
    children,
    textContent: opts.text || '',
    disabled: !!opts.disabled,
    clicks: 0,
    getAttribute(name) { return attrs[name] ?? null; },
    getClientRects() { return { length: opts.hidden ? 0 : 1 }; },
    click() { if (!this.disabled) this.clicks++; }, // like a disabled <button>
  });
}

/** doc([elements], window?) */
function doc(children, win) {
  return queryable({ children, defaultView: win });
}

/** A window that records dispatched events. */
function fakeWindow() {
  const dispatched = [];
  function KeyboardEvent(type, init) { Object.assign(this, init, { type }); }
  return { dispatched, KeyboardEvent, dispatchEvent(e) { dispatched.push(e); return true; } };
}

module.exports = { el, doc, fakeWindow };
