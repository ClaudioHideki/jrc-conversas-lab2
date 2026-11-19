import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { migrationPath, ivrMigrationPath, reviewedMigrations, verifyAccessMigration, verifyReviewedMigrations } from './validate_cc_access_migration.mjs';

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

const reviewedChanges = Object.keys(reviewedMigrations).map(path => `A\t${path}`).join('\n');
const readReviewed = path => readFileSync(new URL('../' + path, import.meta.url));

test('current candidate admits all three exact hash-pinned additions regardless of Git output order', () => {
  const reversed = reviewedChanges.split('\n').reverse().join('\n');
  assert.equal(verifyReviewedMigrations(reversed, readReviewed, schema).migrationCount, 3);
});

for (const change of ['', addition, `A\t${ivrMigrationPath}`, reviewedChanges + `\nM\tdb/schema.rb`,
  reviewedChanges + `\nM\tdb/sql/historical.sql`, reviewedChanges + `\nD\tdb/migrate/20260101000000_original.rb`,
  reviewedChanges + `\nA\tdb/migrate/20261117210000_unknown.rb`, reviewedChanges.replace('A\t', 'M\t'),
  reviewedChanges + `\nA\t${ivrMigrationPath}`]) {
  test(`rejects incomplete, duplicate or unreviewed ledger admission ${JSON.stringify(change)}`, () => {
    assert.throws(() => verifyReviewedMigrations(change, readReviewed, schema));
  });
}

for (const path of Object.keys(reviewedMigrations)) {
  test(`rejects a one-byte mutation of ${path} while preserving its timestamp`, () => {
    const altered = key => key === path ? Buffer.concat([readReviewed(key), Buffer.from('\n')]) : readReviewed(key);
    assert.throws(() => verifyReviewedMigrations(reviewedChanges, altered, schema));
  });
}

test('ledger admission retains the forward-only timestamp protection', () => {
  assert.throws(() => verifyReviewedMigrations(reviewedChanges, readReviewed, schema.replace('2026_11_16_190000', '2026_11_18_190000')));
});
