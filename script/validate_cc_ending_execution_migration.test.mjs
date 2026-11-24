import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import { sourcePins, validateEndingExecutionSources } from './validate_cc_ending_execution_migration.mjs';

const contents = Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) =>
  [key, readFileSync(new URL('../' + pin.path, import.meta.url))]));

test('accepts only exact pinned bytes and never claims native acceptance', () => {
  const proof = validateEndingExecutionSources(contents);
  assert.equal(proof.source_identity_verified, true);
  assert.equal(proof.native_schema_or_execution_accepted, false);
  assert(Object.isFrozen(sourcePins));
  assert(Object.values(sourcePins).every(pin => Object.isFrozen(pin)));
});

for (const key of Object.keys(sourcePins)) {
  test(`rejects omitted ${key}`, () => {
    const altered = { ...contents };
    delete altered[key];
    assert.throws(() => validateEndingExecutionSources(altered));
  });
  test(`rejects changed ${key}`, () => {
    const altered = { ...contents, [key]: Buffer.concat([contents[key], Buffer.from('\n')]) };
    assert.throws(() => validateEndingExecutionSources(altered));
  });
}

test('rejects unknown source even if the exact three known sources are included', () => {
  assert.throws(() => validateEndingExecutionSources({ ...contents, unreviewed: Buffer.from('SYNTHETIC') }));
});
