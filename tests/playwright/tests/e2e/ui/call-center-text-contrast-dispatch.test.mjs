import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import {
  measureTextContrast,
  measureLocatorTextContrast,
} from './call-center-text-contrast.mjs';

// Dispatch regression only. These tests deliberately do not claim real browser CSS or WCAG acceptance.
test('reproduces the previous direct Node invocation without pretending a Node DOM exists', () => {
  assert.equal(typeof document, 'undefined');
  assert.throws(() => measureTextContrast({}), /document is not defined/);
  const source = fs.readFileSync(
    new URL('./call-center-text-contrast.mjs', import.meta.url),
    'utf8'
  );
  const original = source.slice(0, source.indexOf('\n// Locator calls'));
  assert.equal(
    createHash('sha256').update(original).digest('hex'),
    '96743e2c8d8fd56fbfbb05d59621ba2790ab4a29aa1f65f39f1f668343e31a1c'
  );
});

test('delegates the unchanged measurement function to the locator browser context and returns its exact result', async () => {
  const actual = {
    foreground: [0, 0, 0, 255],
    background: [255, 255, 255, 255],
    ratio: 21,
  };
  let calls = 0;
  const names = [
    'call-center-native.spec.ts',
    'call-center-quality-review-native.mjs',
    'call-center-transcript-native.mjs',
    'call-center-recording-context-native.mjs',
    'call-center-quality-history-native.mjs',
  ];
  names.forEach(name => {
    const source = fs.readFileSync(new URL(name, import.meta.url), 'utf8');
    assert.match(
      source,
      /import\s*\{\s*measureLocatorTextContrast\s+as\s+(?:measureTextContrast|contrast),?\s*\}\s*from '\.\/call-center-text-contrast\.mjs';/
    );
    assert.match(source, /toBeGreaterThanOrEqual\(4\.5\)/);
  });
  const locator = {
    evaluate: async fn => {
      calls += 1;
      assert.equal(fn, measureTextContrast);
      return [actual];
    },
  };
  assert.equal(await measureLocatorTextContrast(locator), actual);
  assert.equal(calls, 1);
});

test('rejects missing multiple or nonfinite measurements rather than inventing a passing contrast', async () => {
  const variants = [
    null,
    [],
    [{ ratio: 21 }, { ratio: 21 }],
    [{ ratio: Number.NaN }],
    [{ ratio: undefined }],
  ];
  await Promise.all(
    variants.map(async value => {
      const locator = { evaluate: async () => value };
      await assert.rejects(
        measureLocatorTextContrast(locator),
        /Expected one actual browser text-contrast measurement/
      );
    })
  );
});

test('preserves low contrast and propagates a browser failure for the real acceptance assertions', async () => {
  const actual = { ratio: 1.1 };
  assert.equal(
    (await measureLocatorTextContrast({ evaluate: async () => [actual] }))
      .ratio,
    1.1
  );
  const failure = new Error('SYNTHETIC browser-context failure');
  await assert.rejects(
    measureLocatorTextContrast({
      evaluate: async () => {
        throw failure;
      },
    }),
    failure
  );
});
