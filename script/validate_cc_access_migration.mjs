import { sourcePins as endingReadinessPins, validateEndingReadinessSources } from './validate_cc_ending_readiness_migration.mjs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';
import { sourcePins as endingOriginPins, validateEndingOriginSources } from './validate_cc_ending_origin_migration.mjs';

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
export const audioInspectionMigrationPath = 'db/migrate/20261120153000_create_contact_center_audio_inspections.rb';
export const audioInspectionMigrationHash = '4415dbe1ca204bbe35e9fb0567aa05cecbdcf32e7a20afd6406188d94e31163f';
export const qualityReviewMigrationPath = 'db/migrate/20261121003000_add_contact_center_quality_review_authority.rb';
export const qualityReviewMigrationHash = '1e40fdf573254db5aae23d7474db96c2052818532c0ca0cc5b398807df889cd0';
export const teamSupervisionMigrationPath = 'db/migrate/20261121090000_create_contact_center_team_supervisions.rb';
export const teamSupervisionMigrationHash = 'eab5fb4a891c52e72879eb306d3f31913d59c59af5b3eea641229e785479cf2d';
export const audioInspectionSqlSources = Object.freeze({
  'lib/jrc_contact_center/audio_inspection_sql.rb': 'd7a42667936a6dda80a42d63e2e4bfc2a4857fc5fe3712ee0f047f2e6bfbb73f',
  'lib/jrc_contact_center/audio_inspection_schema_receipt.rb': '8cb4e61c65722e24e5c541f098b6682d0056f56e4792a1e189dd81cf41f372b5',
});
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
  [audioInspectionMigrationPath]: audioInspectionMigrationHash,
  [qualityReviewMigrationPath]: qualityReviewMigrationHash,
  [teamSupervisionMigrationPath]: teamSupervisionMigrationHash,
});
export const pauseApprovalMigrationPath = 'db/migrate/20261122120000_create_contact_center_pause_approval_evidence.rb';
export const pauseApprovalMigrationHash = '176838ffaf8c38cb29cae77a600af32bce5cfe115062a867b42c9e31046f043b';
export const pauseApprovalSqlSources = Object.freeze({
  "db/functions/20261122120000_contact_center_pause_approval_evidence.sql": "98db0077317bf9a8df0e94a2f403913e022ea1db91d0059f883c474d2a4a19e3",
  "lib/jrc_contact_center/pause_approval_schema_receipt.rb": "2ff201721493e14ea1090d185177f86180cfa844362b7f3c61a1068c9629e653"
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
// The current candidate admits exactly twelve reviewed forward additions, never an arbitrary extra migration.
export function verifyReviewedMigrations(changes, readCurrent, schema) {
  const expected = Object.keys(reviewedMigrations).sort();
  const rows = changes.trim().split('\n').filter(Boolean).sort();
  if (JSON.stringify(rows) !== JSON.stringify(expected.map(path => `A\t${path}`))) {
    throw new Error('Only the twelve exact reviewed additions are admitted; historical migrations/schema/SQL remain protected.');
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
  for (const [path, expectedHash] of Object.entries(audioInspectionSqlSources)) {
    if (createHash('sha256').update(readCurrent(path)).digest('hex') !== expectedHash)
      throw new Error(`Reviewed audio inspection SQL/receipt source changed: ${path}`);
  }
  return validateNewMigrationTimestamps(schema, expected);
}

// Current exact admission adds one empty evidence domain. The original1/12verifiers and every historical hash remain unchanged.
export function verifyPauseApprovalMigrations(changes, readCurrent, schema) {
  const migrations = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath].sort();
  const sqlPaths = Object.keys(pauseApprovalSqlSources).filter(path => path.startsWith('db/'));
  const expected = [...migrations, ...sqlPaths].map(path => `A\t${path}`).sort();
  const rows = changes.trim().split('\n').filter(Boolean).sort();
  if (JSON.stringify(rows) !== JSON.stringify(expected))
    throw new Error('Only13exact reviewed migrations and their exact additive SQL are admitted; all other database changes remain blocked.');
  if (createHash('sha256').update(readCurrent(pauseApprovalMigrationPath)).digest('hex') !== pauseApprovalMigrationHash)
    throw new Error('Reviewed pause approval migration content changed.');
  for (const [path, expectedHash] of Object.entries(pauseApprovalSqlSources)) {
    if (createHash('sha256').update(readCurrent(path)).digest('hex') !== expectedHash)
      throw new Error(`Reviewed pause approval SQL/receipt source changed: ${path}`);
  }
  const legacyChanges = Object.keys(reviewedMigrations).map(path => `A\t${path}`).join('\n');
  verifyReviewedMigrations(legacyChanges, readCurrent, schema);
  return validateNewMigrationTimestamps(schema, migrations);
}

export const endingConfirmationMigrationPath = 'db/migrate/20261122212900_create_contact_center_ending_reason_confirmations.rb';
export const endingConfirmationMigrationHash = '37c558d6e6ab87733b4e934325f88640ba043b7fc242f39940501f6e71d17725';
export const endingConfirmationSources = Object.freeze({
  'db/functions/20261122212900_contact_center_ending_confirmations.sql': '544a195a90dea477d747c9cd08cf749bebc5d33bc0283c3bc1c11661406be681',
  'lib/jrc_contact_center/ending_confirmation_schema_receipt.rb': 'cb6c9d0365680e9a64ca88c96240ea0dbe20072f11281f17d2ac7e529cc8438f',
});

// Preserve the published1/12/13verifiers; this explicit addition admits no unknown migration or SQL.
export function verifyEndingConfirmationMigrations(changes, readCurrent, schema) {
  const newPaths = [endingConfirmationMigrationPath, ...Object.keys(endingConfirmationSources).filter(path => path.startsWith('db/'))];
  const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath,
    ...Object.keys(pauseApprovalSqlSources).filter(path => path.startsWith('db/'))];
  const rows = changes.trim().split('\n').filter(Boolean).sort();
  const expected = [...priorPaths, ...newPaths].map(path => `A\t${path}`).sort();
  if (JSON.stringify(rows) !== JSON.stringify(expected))
    throw new Error('Only14exact reviewed forward migrations and their exact SQL are admitted; unknown database changes remain blocked.');
  for (const [path, digest] of Object.entries({ [endingConfirmationMigrationPath]: endingConfirmationMigrationHash, ...endingConfirmationSources })) {
    if (createHash('sha256').update(readCurrent(path)).digest('hex') !== digest)
      throw new Error(`Reviewed ending confirmation source changed: ${path}`);
  }
  verifyPauseApprovalMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), readCurrent, schema);
  return validateNewMigrationTimestamps(schema, [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath]);
}


export const endingActionScopeMigrationPath = 'db/migrate/20261123034500_create_contact_center_ending_action_scopes.rb';
export const endingActionScopeMigrationHash = 'deaaea240d744f923541b97c404cd9c5502722f9169f971e3ffb16595fe3deac';
export const endingActionScopeSources = Object.freeze({
  "db/functions/20261123034500_contact_center_ending_action_scopes.sql": "3f1ecc42e7944d40ddd838eb066dc1610a95465f27f614b11f692f9d1ee7fdd5",
  "lib/jrc_contact_center/ending_action_scope_schema_receipt.rb": "d23faa6189bae4c4ca93084e8c085f7839caa5f8383a8b6deb8fa248fdb68bb1"
});

// The original1/12/13/14verifiers and their exact historical hashes remain unchanged.
export function verifyEndingActionScopeMigrations(changes, readCurrent, schema) {
  const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath,
    ...Object.keys(pauseApprovalSqlSources).filter(path => path.startsWith('db/')),
    ...Object.keys(endingConfirmationSources).filter(path => path.startsWith('db/'))];
  const newPaths = [endingActionScopeMigrationPath, ...Object.keys(endingActionScopeSources).filter(path => path.startsWith('db/'))];
  const rows = changes.trim().split('\n').filter(Boolean).sort();
  const expected = [...priorPaths, ...newPaths].map(path => `A\t${path}`).sort();
  if (JSON.stringify(rows) !== JSON.stringify(expected))
    throw new Error('Only15exact reviewed forward migrations and their exact SQL are admitted; unknown database changes remain blocked.');
  for (const [path, digest] of Object.entries({ [endingActionScopeMigrationPath]: endingActionScopeMigrationHash, ...endingActionScopeSources })) {
    if (createHash('sha256').update(readCurrent(path)).digest('hex') !== digest)
      throw new Error(`Reviewed ending action scope source changed: ${path}`);
  }
  verifyEndingConfirmationMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), readCurrent, schema);
  return validateNewMigrationTimestamps(schema,
    [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath, endingActionScopeMigrationPath]);
}


export const endingActionVersionMigrationPath = 'db/migrate/20261123063000_create_contact_center_ending_action_versions.rb';
export const endingActionVersionMigrationHash = 'e22b6a5f6d6fd239e18a7d83862cee391159acea181c0338d72daf7c1da75dc0';
export const endingActionVersionSources = Object.freeze({
  "db/functions/20261123063000_contact_center_ending_action_versions.sql": "0d8c92f02f01f49f3a783bc468bfd20e1e37fc86bfca6b2409cea69bec12c253",
  "lib/jrc_contact_center/ending_action_version_schema_receipt.rb": "bae3d97965ae0a0e84917dab6709b7dc03561a46f5fe4db718e826b7796ee397"
});

// The installation checks these hashes again. A top-level source admission must
// not accept a candidate whose own migration still pins an older receipt.
export function verifyEndingActionVersionSourcePins(readCurrent) {
  const migration = readCurrent(endingActionVersionMigrationPath).toString('utf8');
  for (const [path, digest] of Object.entries(endingActionVersionSources)) {
    const key = path.startsWith('db/') ? 'SQL' : `'${path}'`;
    if (!migration.includes(`${key} => '${digest}'`))
      throw new Error(`Private version migration source pin mismatch: ${path}`);
  }
}

// Keep every earlier verifier and source hash. This addition admits only its3exact private-history sources.
export function verifyEndingActionVersionMigrations(changes, readCurrent, schema) {
  const priorPaths = [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath, endingActionScopeMigrationPath,
    ...Object.keys(pauseApprovalSqlSources).filter(path => path.startsWith('db/')),
    ...Object.keys(endingConfirmationSources).filter(path => path.startsWith('db/')),
    ...Object.keys(endingActionScopeSources).filter(path => path.startsWith('db/'))];
  const newPaths = [endingActionVersionMigrationPath, ...Object.keys(endingActionVersionSources).filter(path => path.startsWith('db/'))];
  const rows = changes.trim().split('\n').filter(Boolean).sort();
  const expected = [...priorPaths, ...newPaths].map(path => `A\t${path}`).sort();
  if (JSON.stringify(rows) !== JSON.stringify(expected))
    throw new Error('Only16exact reviewed forward migrations and their exact SQL are admitted; unknown database changes remain blocked.');
  for (const [path, digest] of Object.entries({ [endingActionVersionMigrationPath]: endingActionVersionMigrationHash, ...endingActionVersionSources })) {
    if (createHash('sha256').update(readCurrent(path)).digest('hex') !== digest)
      throw new Error(`Reviewed ending action private version source changed: ${path}`);
  }
  verifyEndingActionVersionSourcePins(readCurrent);
  verifyEndingActionScopeMigrations(priorPaths.map(path => `A\t${path}`).join('\n'), readCurrent, schema);
  return validateNewMigrationTimestamps(schema,
    [...Object.keys(reviewedMigrations), pauseApprovalMigrationPath, endingConfirmationMigrationPath,
      endingActionScopeMigrationPath, endingActionVersionMigrationPath]);
}

// Preserve all sixteen previous verifiers and source identities. Only the exact
// new origin migration and its SQL may be removed before the prior strict gate.
export function verifyEndingOriginMigrations(changes, readCurrent, schema) {
  const additions = [endingOriginPins.migration.path, endingOriginPins.sql.path];
  const rows = changes.trim().split('\n').filter(Boolean);
  for (const path of additions) {
    if (rows.filter(row => row === `A\t${path}`).length !== 1)
      throw new Error(`Missing or duplicate reviewed ending origin source: ${path}`);
  }
  const prior = rows.filter(row => !additions.some(path => row === `A\t${path}`));
  verifyEndingActionVersionMigrations(prior.join('\n'), readCurrent, schema);
  validateEndingOriginSources(Object.fromEntries(Object.entries(endingOriginPins).map(([key, pin]) => [key, readCurrent(pin.path)])));
  const migrations = rows.filter(row => row.startsWith('A\tdb/migrate/')).map(row => row.slice(2));
  return validateNewMigrationTimestamps(schema, migrations);
}

// Admit only the exact eighteenth migration/SQL before the unchanged
// seventeen-migration gate; unknown, modified or duplicate sources still fail.
export function verifyEndingReadinessMigrations(changes, readCurrent, schema) {
  const additions = [endingReadinessPins.migration.path, endingReadinessPins.sql.path];
  const rows = changes.trim().split('\n').filter(Boolean);
  for (const path of additions) {
    if (rows.filter(row => row === `A\t${path}`).length !== 1)
      throw new Error(`Missing or duplicate reviewed ending readiness source: ${path}`);
  }
  const prior = rows.filter(row => !additions.some(path => row === `A\t${path}`));
  verifyEndingOriginMigrations(prior.join('\n'), readCurrent, schema);
  validateEndingReadinessSources(Object.fromEntries(Object.entries(endingReadinessPins).map(([key, pin]) => [key, readCurrent(pin.path)])));
  return validateNewMigrationTimestamps(schema, rows.filter(row => row.startsWith('A\tdb/migrate/')).map(row => row.slice(2)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const changes = execFileSync('git', ['diff', '--name-status', base, 'HEAD', '--', 'db/migrate', 'db/schema.rb', 'db/sql', 'db/functions'], { encoding: 'utf8' });
  const schema = execFileSync('git', ['show', `${base}:db/schema.rb`], { encoding: 'utf8' });
  const result = verifyEndingReadinessMigrations(changes, readFileSync, schema);
  console.log(JSON.stringify({ protectedBase: base, reviewedMigrations: { ...reviewedMigrations,
    [pauseApprovalMigrationPath]: pauseApprovalMigrationHash, [endingConfirmationMigrationPath]: endingConfirmationMigrationHash, [endingActionScopeMigrationPath]: endingActionScopeMigrationHash, [endingActionVersionMigrationPath]: endingActionVersionMigrationHash },
    pauseApprovalSqlSources, endingConfirmationSources, endingActionScopeSources, endingActionVersionSources, endingOriginPins, ...result }));
}
