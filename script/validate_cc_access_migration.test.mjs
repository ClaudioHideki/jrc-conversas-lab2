import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { migrationPath, verifyAccessMigration } from './validate_cc_access_migration.mjs';

const content = readFileSync(new URL('../db/migrate/20261117190000_add_contact_center_access_grants.rb', import.meta.url));
const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const addition = `A\t${migrationPath}`;

test('accepts only the exact reviewed additive migration', () => {
  assert.equal(verifyAccessMigration(addition, content, schema).migrationCount, 1);
});

for (const change of ['', `M\t${migrationPath}`, `${addition}\nM\tdb/schema.rb`, `${addition}\nM\tdb/sql/historical.sql`,
  `${addition}\nA\tdb/migrate/20261117191000_unreviewed.rb`, `${addition}\nD\tdb/migrate/20260101000000_historical.rb`]) {
  test(`rejects unreviewed database change ${JSON.stringify(change)}`, () => {
    assert.throws(() => verifyAccessMigration(change, content, schema));
  });
}

test('rejects even a one-byte mutation of the reviewed migration', () => {
  assert.throws(() => verifyAccessMigration(addition, Buffer.concat([content, Buffer.from('\n')]), schema));
});

test('keeps the timestamp protection against a newer base schema', () => {
  assert.throws(() => verifyAccessMigration(addition, content, schema.replace('2026_11_16_190000', '2026_11_18_190000')));
});
