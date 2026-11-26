import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import {
  reviewedMigrations, pauseApprovalMigrationPath, pauseApprovalSqlSources,
  endingConfirmationMigrationPath, endingConfirmationSources,
  endingActionScopeMigrationPath, endingActionScopeSources,
  endingActionVersionMigrationPath, endingActionVersionSources,
  verifyNicoDispatchIntentMigrations, verifyTypedDestinationMigrations, verifyQualityReviewMigrations,
  nicoDispatchIntentMigrationPath,
} from './validate_cc_access_migration.mjs';
import { sourcePins as origin } from './validate_cc_ending_origin_migration.mjs';
import { sourcePins as readiness } from './validate_cc_ending_readiness_migration.mjs';
import { sourcePins as execution } from './validate_cc_ending_execution_migration.mjs';
import { sourcePins as attempt } from './validate_cc_ending_attempt_migration.mjs';
import { sourcePins as typed } from './validate_cc_typed_destination_migration.mjs';
import { sourcePins, validateQualityReviewSources } from './validate_cc_quality_review_migration.mjs';

const schema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_16_190000) do\nend';
const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath,
  endingConfirmationMigrationPath, endingActionScopeMigrationPath, endingActionVersionMigrationPath,
  ...[pauseApprovalSqlSources, endingConfirmationSources, endingActionScopeSources, endingActionVersionSources]
    .flatMap(sources => Object.keys(sources).filter(path => path.startsWith('db/'))),
  ...[origin, readiness, execution, attempt].flatMap(pins => [pins.migration.path, pins.sql.path]), nicoDispatchIntentMigrationPath];
const paths = [...priorPaths, typed.migration.path, typed.sql.path, sourcePins.migration.path, sourcePins.sql.path];
const changes = paths.map(path => `A\t${path}`).join('\n');
const read = path => readFileSync(new URL('../' + path, import.meta.url));
const contents = Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, read(pin.path)]));

test('admits exactly M23 after the unchanged M22 verifier rejects the extra sources', () => {
  assert.throws(() => verifyTypedDestinationMigrations(changes, read, schema));
  assert.equal(verifyQualityReviewMigrations(changes, read, schema).migrationCount, 23);
  assert.equal(verifyQualityReviewMigrations(changes.split('\n').reverse().join('\n'), read, schema).migrationCount, 23);
  assert.equal(validateQualityReviewSources(contents).native_schema_or_execution_accepted, false);
});
for (const missing of paths) {
  test(`still refuses omission of historical or new source ${missing}`, () => {
    assert.throws(() => verifyQualityReviewMigrations(paths.filter(path => path !== missing).map(path => `A\t${path}`).join('\n'), read, schema));
  });
}
for (const changed of [...paths, ...[origin, readiness, execution, attempt, typed, sourcePins].map(pins => pins.receipt.path)]) {
  test(`still refuses altered historical or new content ${changed}`, () => {
    assert.throws(() => verifyQualityReviewMigrations(changes, path => path === changed ? Buffer.concat([read(path), Buffer.from('\n')]) : read(path), schema));
  });
}
for (const extra of [`A\t${sourcePins.migration.path}`, `A\t${sourcePins.sql.path}`, 'M\tdb/schema.rb',
  `M\t${typed.migration.path}`, 'D\tdb/migrate/20260101000000_history.rb',
  'A\tdb/migrate/20261126193001_unknown.rb', 'A\tdb/functions/unreviewed.sql']) {
  test(`still refuses unknown mutation ${extra}`, () => {
    assert.throws(() => verifyQualityReviewMigrations(changes + '\n' + extra, read, schema));
  });
}
test('never relaxes the forward timestamp barrier', () => {
  assert.throws(() => verifyQualityReviewMigrations(changes, read, schema.replace('2026_11_16_190000', '2026_11_27_120000')));
});
for (const key of Object.keys(sourcePins)) {
  test(`refuses absent or malformed bounded human quality source ${key}`, () => {
    const missing = { ...contents };
    delete missing[key];
    assert.throws(() => validateQualityReviewSources(missing));
    for (const value of [null, '', Buffer.alloc(0), Buffer.alloc(400001), contents[key].toString('utf8')])
      assert.throws(() => validateQualityReviewSources({ ...contents, [key]: value }));
  });
}
test('never treats an unreviewed additional source or a static source hash as native acceptance', () => {
  assert.throws(() => validateQualityReviewSources({ ...contents, extra: Buffer.from('SYNTHETIC') }));
  const proof = validateQualityReviewSources(contents);
  assert.equal(proof.static_only, true);
  assert.equal(proof.source_identity_verified, true);
  assert.equal(proof.native_schema_or_execution_accepted, false);
});
