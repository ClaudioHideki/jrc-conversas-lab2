import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import {
  REVIEWED_BASE, REVIEWED_SOURCE, validateHistoricalMigrationAdmission,
} from './validate_ag_historical_migrations.mjs';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const old = 'db/migrate/20261101210000_old_reviewed.rb';
const forward = 'db/migrate/20261110190000_forward_reviewed.rb';
const sql = 'db/functions/20261101210000_old_reviewed.sql';

function fixture() {
  const baseSchema = 'ActiveRecord::Schema[7.1].define(version: 2026_11_09_160000) do\nend\n';
  const files = { [old]: "execute Rails.root.join('db/functions/20261101210000_old_reviewed.sql').read\n",
    [forward]: 'class ForwardReviewed; end\n', [sql]: 'SELECT 1;\n' };
  const audited = { ...files };
  return {
    files, audited,
    input: {
      baseSha: REVIEWED_BASE, baseSchema,
      manifest: {
        format_version: 1, base_sha: REVIEWED_BASE, audited_source_sha: REVIEWED_SOURCE,
        base_schema_sha256: hash(baseSchema),
        migrations: [old, forward].map((path, i) => ({
          path, version: path.match(/(\d{14})_/)[1], sha256: hash(files[path]),
          historical: i === 0, requires_execution: true, depends_on: [],
          sql_dependencies: i === 0 ? [sql] : [],
        })),
        sql_dependencies: [{ path: sql, sha256: hash(files[sql]) }],
      },
      addedPaths: [old, forward], auditedAddedPaths: [old, forward],
      baseMigrationPaths: ['db/migrate/20261109160000_main.rb'], changedBasePaths: [],
      readCurrent: name => files[name], readAudited: name => audited[name],
    },
  };
}

test('admits only the exact reviewed historical bytes and retains forward validation', () => {
  const { input } = fixture();
  assert.deepEqual(validateHistoricalMigrationAdmission(input), {
    baseSchemaVersion: '20261109160000', migrationCount: 2, historicalCount: 1, forwardCount: 1,
  });
  assert.throws(() => validateNewMigrationTimestamps(input.baseSchema, [old]), /must sort after/);
});

const rejected = [
  ['another base', f => { f.input.baseSha = 'main'; }],
  ['another audited source', f => { f.input.manifest.audited_source_sha = 'a'.repeat(40); }],
  ['changed base schema', f => { f.input.baseSchema += '# unexpected\n'; }],
  ['new unreviewed historical migration', f => { f.input.addedPaths.push('db/migrate/20261101200000_unreviewed.rb'); }],
  ['removed historical migration', f => { f.input.addedPaths = [forward]; }],
  ['modified historical bytes', f => { f.files[old] += '# changed\n'; }],
  ['modified reviewed forward bytes', f => { f.files[forward] += '# changed\n'; }],
  ['invented reviewed hash', f => { f.files[old] += '# changed\n'; f.input.manifest.migrations[0].sha256 = hash(f.files[old]); }],
  ['modified historical SQL', f => { f.files[sql] = 'SELECT 2;\n'; }],
  ['missing SQL inventory', f => { f.input.manifest.sql_dependencies = []; }],
  ['hidden SQL dependency', f => { f.input.manifest.migrations[0].sql_dependencies = []; }],
  ['duplicate SQL dependency', f => { f.input.manifest.sql_dependencies.push({ ...f.input.manifest.sql_dependencies[0] }); }],
  ['duplicate migration entry', f => { f.input.manifest.migrations.push({ ...f.input.manifest.migrations[0] }); }],
  ['invented migration entry', f => { f.input.manifest.migrations.push({ ...f.input.manifest.migrations[0], path: 'db/migrate/20261101200000_unknown.rb' }); }],
  ['false already-applied claim', f => { f.input.manifest.migrations[0].requires_execution = false; }],
  ['false forward classification', f => { f.input.manifest.migrations[0].historical = false; }],
  ['later dependency', f => { f.input.manifest.migrations[0].depends_on = [forward]; }],
  ['modified existing main migration', f => { f.input.changedBasePaths = ['db/migrate/20261109160000_main.rb']; }],
  ['renamed existing main migration', f => { f.input.changedBasePaths = ['db/migrate/20261109160000_main.rb']; f.input.addedPaths.push('db/migrate/20261111100000_renamed.rb'); }],
  ['collision with a main version', f => { f.input.addedPaths.push('db/migrate/20261109160000_collision.rb'); }],
  ['collision between new versions', f => { f.input.addedPaths.push('db/migrate/20261101210000_collision.rb'); }],
];
for (const [name, mutate] of rejected) {
  test('fails closed: ' + name, () => {
    const f = fixture();
    mutate(f);
    assert.throws(() => validateHistoricalMigrationAdmission(f.input));
  });
}

test('a genuinely new forward migration remains subject to the original policy', () => {
  const { input } = fixture();
  input.addedPaths.push('db/migrate/20261111190000_new_forward.rb');
  assert.equal(validateHistoricalMigrationAdmission(input).forwardCount, 2);
});

test('an equal-to-base unreviewed migration stays blocked', () => {
  const { input } = fixture();
  input.addedPaths.push('db/migrate/20261109160000_unreviewed.rb');
  input.baseMigrationPaths = [];
  assert.throws(() => validateHistoricalMigrationAdmission(input), /must sort after/);
});
