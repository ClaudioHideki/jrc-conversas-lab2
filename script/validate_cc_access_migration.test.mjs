import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { migrationPath, ivrMigrationPath, endingReasonSqlPath, endingReasonCatalogSqlPath, reviewedMigrations, audioFileSqlSources, audioInspectionSqlSources, verifyAccessMigration, verifyReviewedMigrations,
  pauseApprovalMigrationPath, pauseApprovalSqlSources, verifyPauseApprovalMigrations } from './validate_cc_access_migration.mjs';

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

test('current candidate admits all twelve exact hash-pinned additions regardless of Git output order', () => {
  const reversed = reviewedChanges.split('\n').reverse().join('\n');
  assert.equal(verifyReviewedMigrations(reversed, readReviewed, schema).migrationCount, 12);
});

for (const omitted of Object.keys(reviewedMigrations)) {
  test(`rejects an incomplete current migration set missing ${omitted}`, () => {
    const incomplete = Object.keys(reviewedMigrations).filter(path => path !== omitted).map(path => `A\t${path}`).join('\n');
    assert.throws(() => verifyReviewedMigrations(incomplete, readReviewed, schema));
  });
}

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


test('rejects a one-byte mutation in the new SQL helper independently of unchanged migration bytes', () => {
  const altered = key => key === endingReasonSqlPath ? Buffer.concat([readReviewed(key), Buffer.from('\n')]) : readReviewed(key);
  assert.throws(() => verifyReviewedMigrations(reviewedChanges, altered, schema), /Reviewed ending reason SQL source changed/);
});

test('requires the new reviewed SQL helper to exist instead of silently treating it as optional', () => {
  const missing = key => {
    if (key === endingReasonSqlPath) throw new Error('Missing reviewed SQL helper');
    return readReviewed(key);
  };
  assert.throws(() => verifyReviewedMigrations(reviewedChanges, missing, schema), /Missing reviewed SQL helper/);
});


test('rejects a one-byte mutation of the separate catalogue/call SQL while migration and ACW-origin SQL remain unchanged', () => {
  const altered = key => key === endingReasonCatalogSqlPath ? Buffer.concat([readReviewed(key), Buffer.from('\n')]) : readReviewed(key);
  assert.throws(() => verifyReviewedMigrations(reviewedChanges, altered, schema), /Reviewed ending reason SQL source changed/);
});

test('requires the independently reviewed catalogue/call SQL source to exist', () => {
  const missing = key => {
    if (key === endingReasonCatalogSqlPath) throw new Error('Missing catalogue SQL helper');
    return readReviewed(key);
  };
  assert.throws(() => verifyReviewedMigrations(reviewedChanges, missing, schema), /Missing catalogue SQL helper/);
});

for (const path of Object.keys(audioFileSqlSources)) {
  test(`rejects any mutation of reviewed audio storage/origin/receipt source ${path}`, () => {
    const altered = key => key === path ? Buffer.concat([readReviewed(key), Buffer.from('\n')]) : readReviewed(key);
    assert.throws(() => verifyReviewedMigrations(reviewedChanges, altered, schema), /Reviewed private audio SQL\/receipt source changed/);
  });
  test(`requires the exact audio storage/origin/receipt source ${path}`, () => {
    const missing = key => {
      if (key === path) throw new Error('Missing private audio SQL/receipt');
      return readReviewed(key);
    };
    assert.throws(() => verifyReviewedMigrations(reviewedChanges, missing, schema), /Missing private audio SQL\/receipt/);
  });
}

for (const path of Object.keys(audioInspectionSqlSources)) {
  test(`rejects any mutation of the independently reviewed audio inspection source ${path}`, () => {
    const altered = key => key === path ? Buffer.concat([readReviewed(key), Buffer.from('\n')]) : readReviewed(key);
    assert.throws(() => verifyReviewedMigrations(reviewedChanges, altered, schema), /Reviewed audio inspection SQL\/receipt source changed/);
  });
  test(`requires the independently reviewed audio inspection source ${path}`, () => {
    const missing = key => {
      if (key === path) throw new Error('Missing audio inspection SQL/receipt');
      return readReviewed(key);
    };
    assert.throws(() => verifyReviewedMigrations(reviewedChanges, missing, schema), /Missing audio inspection SQL\/receipt/);
  });
}

const pauseDbSql = Object.keys(pauseApprovalSqlSources).filter(path => path.startsWith('db/'));
const currentPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, ...pauseDbSql];
const pauseChanges = currentPaths.map(path => `A\t${path}`).join('\n');

test('current pause candidate requires13exact forward migrations plus the exact new SQL, preserving the old12guard', () => {
  assert.equal(verifyPauseApprovalMigrations(pauseChanges, readReviewed, schema).migrationCount, 13);
  assert.equal(verifyReviewedMigrations(reviewedChanges, readReviewed, schema).migrationCount, 12);
});
for (const omitted of currentPaths) {
  test(`rejects an incomplete pause evidence migration set missing ${omitted}`, () => {
    const incomplete = currentPaths.filter(path => path !== omitted).map(path => `A\t${path}`).join('\n');
    assert.throws(() => verifyPauseApprovalMigrations(incomplete, readReviewed, schema));
  });
}
for (const change of [reviewedChanges, pauseChanges + `\nA\t${pauseApprovalMigrationPath}`,
  pauseChanges + '\nM\tdb/schema.rb', pauseChanges + '\nM\tdb/sql/historical.sql',
  pauseChanges + '\nM\tdb/functions/historical.sql', pauseChanges + '\nA\tdb/functions/unknown.sql',
  pauseChanges + '\nA\tdb/migrate/20261122121000_unknown.rb', pauseChanges.replace('A\t', 'M\t')]) {
  test(`rejects unreviewed pause database changes ${JSON.stringify(change)}`, () => {
    assert.throws(() => verifyPauseApprovalMigrations(change, readReviewed, schema));
  });
}
for (const path of [pauseApprovalMigrationPath, ...Object.keys(pauseApprovalSqlSources)]) {
  test(`rejects a one-byte pause evidence source mutation ${path}`, () => {
    const changed = key => key === path ? Buffer.concat([readReviewed(key), Buffer.from('\n')]) : readReviewed(key);
    assert.throws(() => verifyPauseApprovalMigrations(pauseChanges, changed, schema));
  });
  test(`requires the reviewed pause evidence source ${path}`, () => {
    const missing = key => { if (key === path) throw new Error('Missing reviewed pause evidence'); return readReviewed(key); };
    assert.throws(() => verifyPauseApprovalMigrations(pauseChanges, missing, schema));
  });
}
for (const path of Object.keys(reviewedMigrations)) {
  test(`new admission still rejects a historical migration mutation ${path}`, () => {
    const changed = key => key === path ? Buffer.concat([readReviewed(key), Buffer.from('\n')]) : readReviewed(key);
    assert.throws(() => verifyPauseApprovalMigrations(pauseChanges, changed, schema));
  });
}
test('new admission preserves forward-only timestamp checks against a newer schema base', () => {
  assert.throws(() => verifyPauseApprovalMigrations(pauseChanges, readReviewed,
    schema.replace('2026_11_16_190000', '2026_11_23_120000')));
});
