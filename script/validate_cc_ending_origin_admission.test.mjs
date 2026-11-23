import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  reviewedMigrations, pauseApprovalMigrationPath, pauseApprovalSqlSources,
  endingConfirmationMigrationPath, endingConfirmationSources,
  endingActionScopeMigrationPath, endingActionScopeSources,
  endingActionVersionMigrationPath, endingActionVersionSources,
  verifyEndingOriginMigrations, verifyEndingActionVersionMigrations,
} from './validate_cc_access_migration.mjs';
import { sourcePins } from './validate_cc_ending_origin_migration.mjs';

const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const read = path => readFileSync(new URL('../' + path, import.meta.url));
const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath,
  endingConfirmationMigrationPath, endingActionScopeMigrationPath, endingActionVersionMigrationPath,
  ...[pauseApprovalSqlSources, endingConfirmationSources, endingActionScopeSources, endingActionVersionSources]
    .flatMap(sources => Object.keys(sources).filter(path => path.startsWith('db/')))];
const paths = [...priorPaths, sourcePins.migration.path, sourcePins.sql.path];
const changes = paths.map(path => `A\t${path}`).join('\n');

test('admits exactly seventeen forward migrations and preserves the previous sixteen-source gate', () => {
  assert.equal(verifyEndingOriginMigrations(changes, read, schema).migrationCount, 17);
  assert.equal(verifyEndingActionVersionMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), read, schema).migrationCount, 16);
});

test('accepts reordered Git rows without discarding any source identity', () => {
  assert.equal(verifyEndingOriginMigrations(changes.split('\n').reverse().join('\n'), read, schema).migrationCount, 17);
});

for (const omitted of paths) {
  test(`rejects omission of ${omitted}`, () => {
    assert.throws(() => verifyEndingOriginMigrations(paths.filter(path => path !== omitted).map(path => `A\t${path}`).join('\n'), read, schema));
  });
}

for (const path of [...paths, sourcePins.receipt.path, ...Object.keys(endingActionVersionSources)]) {
  test(`rejects a changed reviewed source ${path}`, () => {
    const changed = key => key === path ? Buffer.concat([read(key), Buffer.from('\n')]) : read(key);
    assert.throws(() => verifyEndingOriginMigrations(changes, changed, schema));
  });
}

for (const extra of [`A\t${sourcePins.migration.path}`, `A\t${sourcePins.sql.path}`, 'M\tdb/schema.rb',
  `M\t${sourcePins.migration.path}`, 'D\tdb/migrate/20260101000000_history.rb',
  'A\tdb/migrate/20261123180001_unknown.rb', 'A\tdb/functions/unreviewed.sql']) {
  test(`rejects duplicate, destructive or unknown database row ${extra}`, () => {
    assert.throws(() => verifyEndingOriginMigrations(changes + '\n' + extra, read, schema));
  });
}

test('retains timestamp protection rather than admitting a retroactive origin migration', () => {
  assert.throws(() => verifyEndingOriginMigrations(changes, read, schema.replace('2026_11_16_190000', '2026_11_24_120000')));
});
