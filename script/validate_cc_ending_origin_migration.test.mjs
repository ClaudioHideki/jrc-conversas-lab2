import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { readEndingOriginSources, validateEndingOriginSources } from './validate_cc_ending_origin_migration.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const read = () => readEndingOriginSources(root);

test('accepts the exact reviewed private source while explicitly declining native acceptance', () => {
  const result = validateEndingOriginSources(read());
  assert.equal(result.static_only, true);
  assert.equal(result.source_identity_verified, true);
  assert.equal(result.native_schema_or_execution_accepted, false);
  assert.equal(result.paths.length, 3);
});

for (const key of ['migration', 'sql', 'receipt']) {
  test(`rejects an independently altered ${key} source`, () => {
    const input = read();
    input[key] = Buffer.concat([input[key], Buffer.from('\n# SYNTHETIC altered source\n')]);
    assert.throws(() => validateEndingOriginSources(input), /Ending origin source differs/);
  });
}

test('rejects missing source rather than treating an incomplete tree as checked', () => {
  const input = read();
  delete input.receipt;
  assert.throws(() => validateEndingOriginSources(input), /Incomplete ending origin source identity/);
});

test('rejects untyped source without coercing an unknown input into a valid identity', () => {
  const input = read();
  input.sql = input.sql.toString('utf8');
  assert.throws(() => validateEndingOriginSources(input), /Invalid ending origin source boundary/);
});
