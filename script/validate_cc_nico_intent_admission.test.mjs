import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  reviewedMigrations, pauseApprovalMigrationPath, pauseApprovalSqlSources,
  endingConfirmationMigrationPath, endingConfirmationSources,
  endingActionScopeMigrationPath, endingActionScopeSources,
  endingActionVersionMigrationPath, endingActionVersionSources,
  verifyEndingAttemptMigrations, verifyNicoDispatchIntentMigrations,
  nicoDispatchIntentMigrationPath,
} from './validate_cc_access_migration.mjs';
import { sourcePins as origin } from './validate_cc_ending_origin_migration.mjs';
import { sourcePins as readiness } from './validate_cc_ending_readiness_migration.mjs';
import { sourcePins as execution } from './validate_cc_ending_execution_migration.mjs';
import { sourcePins as attempt } from './validate_cc_ending_attempt_migration.mjs';

const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath,
  endingConfirmationMigrationPath, endingActionScopeMigrationPath, endingActionVersionMigrationPath,
  ...[pauseApprovalSqlSources, endingConfirmationSources, endingActionScopeSources, endingActionVersionSources]
    .flatMap(sources => Object.keys(sources).filter(path => path.startsWith('db/'))),
  ...[origin, readiness, execution, attempt].flatMap(pins => [pins.migration.path, pins.sql.path])];
const paths = [...priorPaths, nicoDispatchIntentMigrationPath];
const changes = paths.map(path => `A\t${path}`).join('\n');
const read = path => readFileSync(new URL('../' + path, import.meta.url));

test('reproduces the M20 refusal and admits only the separately reviewed exact twenty-first migration', () => {
  assert.throws(() => verifyEndingAttemptMigrations(changes, read, schema));
  assert.equal(verifyNicoDispatchIntentMigrations(changes, read, schema).migrationCount, 21);
  assert.equal(verifyEndingAttemptMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), read, schema).migrationCount, 20);
});

test('preserves complete source identity when rows arrive out of order', () => {
  assert.equal(verifyNicoDispatchIntentMigrations(changes.split('\n').reverse().join('\n'), read, schema).migrationCount, 21);
});

for (const omitted of paths) {
  test(`rejects omission of reviewed identity ${omitted}`, () => {
    const incomplete = paths.filter(path => path !== omitted).map(path => `A\t${path}`).join('\n');
    assert.throws(() => verifyNicoDispatchIntentMigrations(incomplete, read, schema));
  });
}

for (const changed of [...paths, ...[origin, readiness, execution, attempt].map(pins => pins.receipt.path)]) {
  test(`rejects changed protected bytes ${changed}`, () => {
    const altered = path => path === changed ? Buffer.concat([read(path), Buffer.from('\n')]) : read(path);
    assert.throws(() => verifyNicoDispatchIntentMigrations(changes, altered, schema));
  });
}

for (const extra of [`A\t${nicoDispatchIntentMigrationPath}`, 'M\tdb/schema.rb',
  `M\t${attempt.migration.path}`, 'D\tdb/migrate/20260101000000_history.rb',
  'A\tdb/migrate/20261124200001_unknown.rb', 'A\tdb/functions/unreviewed.sql']) {
  test(`rejects duplicate, unknown or destructive source ${extra}`, () => {
    assert.throws(() => verifyNicoDispatchIntentMigrations(changes + '\n' + extra, read, schema));
  });
}

test('preserves the timestamp barrier instead of admitting retroactive source', () => {
  assert.throws(() => verifyNicoDispatchIntentMigrations(changes, read, schema.replace('2026_11_16_190000', '2026_11_25_120000')));
});
