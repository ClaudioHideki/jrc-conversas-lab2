import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

export const migrationPath = 'db/migrate/20261117190000_add_contact_center_access_grants.rb';
export const migrationHash = '85fa579036a807b2d50ae3c30af64b061ba9ea6c6ffe173b4e0f33d4ad922dbe';
export const ivrMigrationPath = 'db/migrate/20261117200000_create_contact_center_ivr_drafts.rb';
export const ivrMigrationHash = 'eaeb4147658fd8e5c9bf25272c34bf5ed3113cf603856854906620f128d92e91';
export const acwFormMigrationPath = 'db/migrate/20261119190000_create_contact_center_acw_forms.rb';
export const acwFormMigrationHash = 'e900938e5ba82f3eb0481773c41f64b5e4d264ee70c110fb8b20c69506200053';
export const deferredPauseMigrationPath = 'db/migrate/20261119193000_create_contact_center_deferred_pause_requests.rb';
export const deferredPauseMigrationHash = '6dff254f8838085a16cd2eb6b4e516d477b8d15c6cba09873e7020ae792c9db2';
export const qualificationFormMigrationPath = 'db/migrate/20261119203000_create_contact_center_qualification_forms.rb';
export const qualificationFormMigrationHash = '6c9c9d3fd89691f7168a493d53e7d0124b72f95908d93cc8d7d96a5fd19eed26';
export const endingReasonMigrationPath = 'db/migrate/20261120023000_create_contact_center_ending_reason_versions.rb';
export const endingReasonMigrationHash = 'e0376ccbd1cb244e447841a2a0b8d32e083eff359a19c25ddfe2304d9c363247';
export const teamStateMigrationPath = 'db/migrate/20261120070000_create_contact_center_team_states.rb';
export const teamStateMigrationHash = '7466db5b4b1823d9d5a7296fd40bcfe405f0f3c78ff6ef902b94cb69228c0d1b';
export const audioFolderMigrationPath = 'db/migrate/20261120090000_create_contact_center_audio_folders.rb';
export const audioFolderMigrationHash = 'ba0f119179aa59ca0b2df5cb9cd9425b2e31f707e8355b6931f495303bb4a8d7';
export const audioFileMigrationPath = 'db/migrate/20261120120000_create_contact_center_audio_files.rb';
export const audioFileMigrationHash = '75cfea1bac450ff452e5cddd61aaf242f6d0f166dc7379a2a12acabb51a738d4';
export const audioFileSqlSources = Object.freeze({
  "lib/jrc_contact_center/audio_file_storage_sql.rb": "78cd8c6013eb8d7378d49c128b87061e442f282f982c13760cc97baebf4558db",
  "lib/jrc_contact_center/audio_file_origin_sql.rb": "19aa49167a6748d7c01af16399456d498ecb16b40600e45b151bcb91c1da5001",
  "lib/jrc_contact_center/audio_file_schema_receipt.rb": "aab9f70fb0f917504ea843fa34bf73d32f9d11292f41581f104f83198086404c"
});
export const endingReasonSqlPath = 'lib/jrc_contact_center/ending_reason_origin_sql.rb';
export const endingReasonSqlHash = 'c0dca8b84c8c4b02d78ed07be4e23bb253f0d64994dccc232ba879941ef35bf8';
export const endingReasonCatalogSqlPath = 'lib/jrc_contact_center/ending_reason_catalog_sql.rb';
export const endingReasonCatalogSqlHash = 'c729952430c681932c3ae7686880cdee96d532f183d2fada33181e0a6ee5445f';
export const reviewedMigrations = Object.freeze({
  [migrationPath]: migrationHash,
  [ivrMigrationPath]: ivrMigrationHash,
  [acwFormMigrationPath]: acwFormMigrationHash,
  [deferredPauseMigrationPath]: deferredPauseMigrationHash,
  [qualificationFormMigrationPath]: qualificationFormMigrationHash,
  [endingReasonMigrationPath]: endingReasonMigrationHash,
  [teamStateMigrationPath]: teamStateMigrationHash,
  [audioFolderMigrationPath]: audioFolderMigrationHash,
  [audioFileMigrationPath]: audioFileMigrationHash,
});
const base = 'a24adc6dd8bb660f955b76cce0172ae1638deee2';

export function verifyAccessMigration(changes, content, schema) {
  const rows = changes.trim().split('\n').filter(Boolean);
  if (rows.length !== 1 || rows[0] !== `A\t${migrationPath}`) {
    throw new Error('Historical migrations, schema and SQL must remain unchanged; only the reviewed addition is allowed.');
  }
  if (createHash('sha256').update(content).digest('hex') !== migrationHash) {
    throw new Error('Reviewed access migration content changed.');
  }
  return validateNewMigrationTimestamps(schema, [migrationPath]);
}

// Preserve the original one-migration verifier and its negative tests above.
// The current candidate admits exactly nine reviewed forward additions, never an arbitrary extra migration.
export function verifyReviewedMigrations(changes, readCurrent, schema) {
  const expected = Object.keys(reviewedMigrations).sort();
  const rows = changes.trim().split('\n').filter(Boolean).sort();
  if (JSON.stringify(rows) !== JSON.stringify(expected.map(path => `A\t${path}`))) {
    throw new Error('Only the nine exact reviewed additions are admitted; historical migrations/schema/SQL remain protected.');
  }
  for (const path of expected) {
    const actual = createHash('sha256').update(readCurrent(path)).digest('hex');
    if (actual !== reviewedMigrations[path]) throw new Error(`Reviewed migration content changed: ${path}`);
  }
  for (const [path, expectedHash] of [[endingReasonSqlPath, endingReasonSqlHash], [endingReasonCatalogSqlPath, endingReasonCatalogSqlHash]]) {
    const sourceHash = createHash('sha256').update(readCurrent(path)).digest('hex');
    if (sourceHash !== expectedHash) throw new Error(`Reviewed ending reason SQL source changed: ${path}`);
  }
  for (const [path, expectedHash] of Object.entries(audioFileSqlSources)) {
    if (createHash('sha256').update(readCurrent(path)).digest('hex') !== expectedHash)
      throw new Error(`Reviewed private audio SQL/receipt source changed: ${path}`);
  }
  return validateNewMigrationTimestamps(schema, expected);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const changes = execFileSync('git', ['diff', '--name-status', base, 'HEAD', '--', 'db/migrate', 'db/schema.rb', 'db/sql'], { encoding: 'utf8' });
  const schema = execFileSync('git', ['show', `${base}:db/schema.rb`], { encoding: 'utf8' });
  const result = verifyReviewedMigrations(changes, readFileSync, schema);
  console.log(JSON.stringify({ protectedBase: base, reviewedMigrations, ...result }));
}
