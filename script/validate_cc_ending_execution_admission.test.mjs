import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  reviewedMigrations, pauseApprovalMigrationPath, pauseApprovalSqlSources,
  endingConfirmationMigrationPath, endingConfirmationSources,
  endingActionScopeMigrationPath, endingActionScopeSources,
  endingActionVersionMigrationPath, endingActionVersionSources,
  verifyEndingReadinessMigrations, verifyEndingExecutionMigrations,
} from './validate_cc_access_migration.mjs';
import { sourcePins as origin } from './validate_cc_ending_origin_migration.mjs';
import { sourcePins as readiness } from './validate_cc_ending_readiness_migration.mjs';
import { sourcePins as execution } from './validate_cc_ending_execution_migration.mjs';

const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const read = path => readFileSync(new URL('../' + path, import.meta.url));
const olderPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath,
  endingActionScopeMigrationPath, endingActionVersionMigrationPath, origin.migration.path, origin.sql.path,
  ...[pauseApprovalSqlSources, endingConfirmationSources, endingActionScopeSources, endingActionVersionSources]
    .flatMap(sources => Object.keys(sources).filter(path => path.startsWith('db/')))];
const priorPaths = [...olderPaths, readiness.migration.path, readiness.sql.path];
const paths = [...priorPaths, execution.migration.path, execution.sql.path];
const changes = paths.map(path => `A\t${path}`).join('\n');

test('admits exactly nineteen sources while preserving the earlier eighteen-migration gate', () => {
  assert.equal(verifyEndingExecutionMigrations(changes, read, schema).migrationCount, 19);
  assert.equal(verifyEndingReadinessMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), read, schema).migrationCount, 18);
});

test('accepts reordered complete rows without discarding any identity', () => {
  assert.equal(verifyEndingExecutionMigrations(changes.split('\n').reverse().join('\n'), read, schema).migrationCount, 19);
});

for (const omitted of paths) {
  test(`rejects omission of ${omitted}`, () => {
    const incomplete = paths.filter(path => path !== omitted).map(path => `A\t${path}`).join('\n');
    assert.throws(() => verifyEndingExecutionMigrations(incomplete, read, schema));
  });
}

for (const path of [...paths, origin.receipt.path, readiness.receipt.path, execution.receipt.path]) {
  test(`rejects changes to protected source ${path}`, () => {
    const changed = key => key === path ? Buffer.concat([read(key), Buffer.from('\n')]) : read(key);
    assert.throws(() => verifyEndingExecutionMigrations(changes, changed, schema));
  });
}

for (const extra of [`A\t${execution.migration.path}`, `A\t${execution.sql.path}`, 'M\tdb/schema.rb',
  `M\t${origin.migration.path}`, 'D\tdb/migrate/20260101000000_history.rb',
  'A\tdb/migrate/20261124000001_unknown.rb', 'A\tdb/functions/unreviewed.sql']) {
  test(`rejects duplicate, unknown or destructive source ${extra}`, () => {
    assert.throws(() => verifyEndingExecutionMigrations(changes + '\n' + extra, read, schema));
  });
}

test('preserves the timestamp barrier against a retroactive execution migration', () => {
  assert.throws(() => verifyEndingExecutionMigrations(changes, read, schema.replace('2026_11_16_190000', '2026_11_25_120000')));
});
