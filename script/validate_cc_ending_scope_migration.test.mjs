import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  reviewedMigrations, endingReasonSqlPath, endingReasonCatalogSqlPath, audioFileSqlSources, audioInspectionSqlSources,
  pauseApprovalMigrationPath, pauseApprovalSqlSources, endingConfirmationMigrationPath, endingConfirmationSources,
  endingActionScopeMigrationPath, endingActionScopeSources, verifyEndingConfirmationMigrations, verifyEndingActionScopeMigrations,
} from './validate_cc_access_migration.mjs';

const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const read = path => readFileSync(new URL('../' + path, import.meta.url));
const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath,
  ...Object.keys(pauseApprovalSqlSources).filter(path => path.startsWith('db/')),
  ...Object.keys(endingConfirmationSources).filter(path => path.startsWith('db/'))];
const paths = [...priorPaths, endingActionScopeMigrationPath, ...Object.keys(endingActionScopeSources).filter(path => path.startsWith('db/'))];
const changes = paths.map(path => `A\t${path}`).join('\n');

test('admits exactly15reviewed forward migrations while preserving the published14verifier', () => {
  assert.equal(verifyEndingActionScopeMigrations(changes, read, schema).migrationCount, 15);
  assert.equal(verifyEndingConfirmationMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), read, schema).migrationCount, 14);
});

test('accepts reordered Git output without discarding duplicate entries', () => {
  assert.equal(verifyEndingActionScopeMigrations(changes.split('\n').reverse().join('\n'), read, schema).migrationCount, 15);
});

for (const omitted of paths) {
  test(`rejects omission of ${omitted}`, () => {
    const incomplete = paths.filter(path => path !== omitted).map(path => `A\t${path}`).join('\n');
    assert.throws(() => verifyEndingActionScopeMigrations(incomplete, read, schema));
  });
}

const protectedPaths = [...new Set([...paths, ...Object.keys(pauseApprovalSqlSources), ...Object.keys(endingConfirmationSources),
  ...Object.keys(endingActionScopeSources), ...Object.keys(audioFileSqlSources), ...Object.keys(audioInspectionSqlSources),
  endingReasonSqlPath, endingReasonCatalogSqlPath])];
for (const path of protectedPaths) {
  test(`rejects any changed historical or new reviewed source ${path}`, () => {
    const mutated = key => key === path ? Buffer.concat([read(key), Buffer.from('\n')]) : read(key);
    assert.throws(() => verifyEndingActionScopeMigrations(changes, mutated, schema));
  });
}

for (const extra of [`A\t${endingActionScopeMigrationPath}`, 'M\tdb/schema.rb', 'M\tdb/functions/historical.sql',
  'D\tdb/migrate/20260101000000_original.rb', 'A\tdb/migrate/20261123034600_unknown.rb', 'A\tdb/functions/unknown.sql']) {
  test(`rejects duplicate, destructive or unknown database change ${extra}`, () => {
    assert.throws(() => verifyEndingActionScopeMigrations(changes + '\n' + extra, read, schema));
  });
}

test('still refuses retroactivity against a newer schema instead of silently waiving timestamp protection', () => {
  assert.throws(() => verifyEndingActionScopeMigrations(changes, read, schema.replace('2026_11_16_190000', '2026_11_24_120000')));
});
