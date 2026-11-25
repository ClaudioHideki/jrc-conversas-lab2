import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  reviewedMigrations, pauseApprovalMigrationPath, pauseApprovalSqlSources,
  endingConfirmationMigrationPath, endingConfirmationSources,
  endingActionScopeMigrationPath, endingActionScopeSources,
  endingActionVersionMigrationPath, endingActionVersionSources,
  verifyNicoDispatchIntentMigrations, verifyTypedDestinationMigrations,
  nicoDispatchIntentMigrationPath,
} from './validate_cc_access_migration.mjs';
import { sourcePins as origin } from './validate_cc_ending_origin_migration.mjs';
import { sourcePins as readiness } from './validate_cc_ending_readiness_migration.mjs';
import { sourcePins as execution } from './validate_cc_ending_execution_migration.mjs';
import { sourcePins as attempt } from './validate_cc_ending_attempt_migration.mjs';
import { sourcePins, validateTypedDestinationSources } from './validate_cc_typed_destination_migration.mjs';

const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath,
  endingConfirmationMigrationPath, endingActionScopeMigrationPath, endingActionVersionMigrationPath,
  ...[pauseApprovalSqlSources, endingConfirmationSources, endingActionScopeSources, endingActionVersionSources]
    .flatMap(sources => Object.keys(sources).filter(path => path.startsWith('db/'))),
  ...[origin, readiness, execution, attempt].flatMap(pins => [pins.migration.path, pins.sql.path]), nicoDispatchIntentMigrationPath];
const paths = [...priorPaths, sourcePins.migration.path, sourcePins.sql.path];
const changes = paths.map(path => `A\t${path}`).join('\n');
const read = path => readFileSync(new URL('../' + path, import.meta.url));
const contents = Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, read(pin.path)]));

test('admits exactly M22 after the unchanged M1-M21 gate refuses the additional sources', () => {
  assert.throws(() => verifyNicoDispatchIntentMigrations(changes, read, schema));
  assert.equal(verifyTypedDestinationMigrations(changes, read, schema).migrationCount, 22);
  assert.equal(verifyNicoDispatchIntentMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), read, schema).migrationCount, 21);
  assert.equal(verifyTypedDestinationMigrations(changes.split('\n').reverse().join('\n'), read, schema).migrationCount, 22);
});
test('exact typed source identity remains static proof and never native acceptance', () => {
  const proof = validateTypedDestinationSources(contents);
  assert.equal(proof.static_only, true);
  assert.equal(proof.source_identity_verified, true);
  assert.equal(proof.native_schema_or_execution_accepted, false);
  assert(Object.isFrozen(sourcePins));
  assert(Object.values(sourcePins).every(Object.isFrozen));
});
for (const omitted of paths) {
  test(`refuses omission of complete historical or new identity ${omitted}`, () => {
    assert.throws(() => verifyTypedDestinationMigrations(paths.filter(path => path !== omitted).map(path => `A\t${path}`).join('\n'), read, schema));
  });
}
for (const changed of [...paths, ...[origin, readiness, execution, attempt].map(pins => pins.receipt.path), sourcePins.receipt.path]) {
  test(`refuses changed historical or new bytes ${changed}`, () => {
    assert.throws(() => verifyTypedDestinationMigrations(changes, path => path === changed ? Buffer.concat([read(path), Buffer.from('\n')]) : read(path), schema));
  });
}
for (const key of Object.keys(sourcePins)) {
  test(`refuses malformed typed source ${key}`, () => {
    const incomplete = { ...contents };
    delete incomplete[key];
    assert.throws(() => validateTypedDestinationSources(incomplete));
    for (const value of [null, '', Buffer.alloc(0), Buffer.alloc(400001), contents[key].toString('utf8')]) {
      assert.throws(() => validateTypedDestinationSources({ ...contents, [key]: value }));
    }
  });
}
test('refuses unreviewed extra source', () => {
  assert.throws(() => validateTypedDestinationSources({ ...contents, extra: Buffer.from('SYNTHETIC') }));
});
for (const extra of [`A\t${sourcePins.migration.path}`, `A\t${sourcePins.sql.path}`, 'M\tdb/schema.rb',
  `M\t${attempt.migration.path}`, 'D\tdb/migrate/20260101000000_history.rb',
  'A\tdb/migrate/20261125060001_unknown.rb', 'A\tdb/functions/unreviewed.sql']) {
  test(`refuses duplicate or unknown mutation ${extra}`, () => {
    assert.throws(() => verifyTypedDestinationMigrations(changes + '\n' + extra, read, schema));
  });
}
test('never relaxes the forward timestamp barrier', () => {
  assert.throws(() => verifyTypedDestinationMigrations(changes, read, schema.replace('2026_11_16_190000', '2026_11_26_120000')));
});
