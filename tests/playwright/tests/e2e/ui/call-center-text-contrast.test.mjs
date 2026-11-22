// Synthetic DOM arithmetic checks only. Actual CSS acceptance still requires all four Chrome projects.
import assert from 'node:assert/strict';
import { afterEach, test } from 'node:test';
import { measureTextContrast } from './call-center-text-contrast.mjs';

const previousDocument = globalThis.document;
const previousStyle = globalThis.getComputedStyle;
afterEach(() => {
  globalThis.document = previousDocument;
  globalThis.getComputedStyle = previousStyle;
});

const node = (foreground, background, parent = null) => ({
  parentElement: parent,
  style: { color: foreground, backgroundColor: background },
});
const installSyntheticCanvas = () => {
  const context = {
    clearRect() {},
    fillRect() {},
    getImageData() {
      assert.ok(Array.isArray(this.fillStyle));
      return { data: this.fillStyle };
    },
  };
  globalThis.document = {
    createElement: () => ({ getContext: () => context }),
  };
  globalThis.getComputedStyle = element => element.style;
};
const black = [0, 0, 0, 255];
const white = [255, 255, 255, 255];
const transparent = [0, 0, 0, 0];

test('reports both black-on-white and white-on-black ratios as 21', () => {
  installSyntheticCanvas();
  for (const [front, back] of [
    [black, white],
    [white, black],
  ])
    assert.equal(measureTextContrast(node(front, back))[0].ratio, 21);
});

test('keeps insufficient grey contrast below the required 4.5 threshold', () => {
  installSyntheticCanvas();
  const row = measureTextContrast(node([119, 119, 119, 255], white))[0];
  assert.ok(row.ratio > 4.47 && row.ratio < 4.5);
});

test('composites transparent ancestors and the nearest opaque surface in DOM order', () => {
  installSyntheticCanvas();
  const root = node(white, transparent, node(black, black, node(black, white)));
  const row = measureTextContrast(root)[0];
  assert.deepEqual(row.background, black);
  assert.equal(row.ratio, 21);
});

test('composites translucent text instead of claiming the opaque source ratio', () => {
  installSyntheticCanvas();
  const row = measureTextContrast(node([255, 255, 255, 128], black))[0];
  assert.deepEqual(row.foreground, [128, 128, 128, 255]);
  assert.ok(row.ratio > 5.3 && row.ratio < 5.4);
});

test('preserves the existing IVR paragraph-then-summary selection and all five rows', () => {
  installSyntheticCanvas();
  const root = node(black, white);
  const paragraphs = Array.from({ length: 4 }, () =>
    node(black, transparent, root)
  );
  const summary = node(white, transparent, root);
  root.querySelectorAll = selector => {
    if (selector === '[data-ivr-calendar-pinned] > p') return paragraphs;
    assert.equal(selector, '[data-ivr-calendar-pinned] summary');
    return [summary];
  };
  const rows = measureTextContrast(root, [
    '[data-ivr-calendar-pinned] > p',
    '[data-ivr-calendar-pinned] summary',
  ]);
  assert.deepEqual(
    rows.map(row => row.ratio),
    [21, 21, 21, 21, 1]
  );
});

test('does not fabricate a passing ratio when the native canvas is unavailable', () => {
  installSyntheticCanvas();
  globalThis.document.createElement = () => ({ getContext: () => null });
  assert.throws(() => measureTextContrast(node(black, white)), TypeError);
});
