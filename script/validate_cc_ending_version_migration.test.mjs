import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  reviewedMigrations, endingReasonSqlPath, endingReasonCatalogSqlPath, audioFileSqlSources, audioInspectionSqlSources,
  pauseApprovalMigrationPath, pauseApprovalSqlSources, endingConfirmationMigrationPath, endingConfirmationSources,
  endingActionScopeMigrationPath, endingActionScopeSources, verifyEndingActionScopeMigrations,
  endingActionVersionMigrationPath, endingActionVersionSources, verifyEndingActionVersionMigrations,
} from './validate_cc_access_migration.mjs';

const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const read = path => readFileSync(new URL('../' + path, import.meta.url));
const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath, endingActionScopeMigrationPath,
  ...Object.keys(pauseApprovalSqlSources).filter(path => path.startsWith('db/')),
  ...Object.keys(endingConfirmationSources).filter(path => path.startsWith('db/')),
  ...Object.keys(endingActionScopeSources).filter(path => path.startsWith('db/'))];
const paths = [...priorPaths, endingActionVersionMigrationPath, ...Object.keys(endingActionVersionSources).filter(path => path.startsWith('db/'))];
const changes = paths.map(path => `A\t${path}`).join('\n');

test('admits exactly16reviewed additions while preserving every previously reviewed verifier and hash', () => {
  assert.equal(verifyEndingActionVersionMigrations(changes, read, schema).migrationCount, 16);
  assert.equal(verifyEndingActionScopeMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), read, schema).migrationCount, 15);
});

test('accepts reordered Git output while keeping complete identity checks', () => {
  assert.equal(verifyEndingActionVersionMigrations(changes.split('\n').reverse().join('\n'), read, schema).migrationCount, 16);
});

for (const omitted of paths) {
  test(`rejects omission of ${omitted}`, () => {
    const incomplete = paths.filter(path => path !== omitted).map(path => `A\t${path}`).join('\n');
    assert.throws(() => verifyEndingActionVersionMigrations(incomplete, read, schema));
  });
}

const protectedPaths = [...new Set([...paths, ...Object.keys(pauseApprovalSqlSources), ...Object.keys(endingConfirmationSources),
  ...Object.keys(endingActionScopeSources), ...Object.keys(endingActionVersionSources),
  ...Object.keys(audioFileSqlSources), ...Object.keys(audioInspectionSqlSources), endingReasonSqlPath, endingReasonCatalogSqlPath])];
for (const path of protectedPaths) {
  test(`rejects any changed historical or new reviewed source ${path}`, () => {
    const mutated = key => key === path ? Buffer.concat([read(key), Buffer.from('\n')]) : read(key);
    assert.throws(() => verifyEndingActionVersionMigrations(changes, mutated, schema));
  });
}

for (const extra of [`A\t${endingActionVersionMigrationPath}`, 'M\tdb/schema.rb', 'M\tdb/functions/historical.sql',
  'D\tdb/migrate/20260101000000_original.rb', 'A\tdb/migrate/20261123063100_unknown.rb', 'A\tdb/functions/unknown.sql']) {
  test(`rejects duplicate, destructive or unknown change ${extra}`, () => {
    assert.throws(() => verifyEndingActionVersionMigrations(changes + '\n' + extra, read, schema));
  });
}

test('rejects retroactivity against a newer schema without waiving the existing timestamp protection', () => {
  assert.throws(() => verifyEndingActionVersionMigrations(changes, read, schema.replace('2026_11_16_190000', '2026_11_24_120000')));
});
