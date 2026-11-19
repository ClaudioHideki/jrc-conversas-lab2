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
export const acwFormMigrationHash = '77dad7bc5bc645324150151fa5aeaba9040104281739ce607c8ff8dd46ae4d0b';
export const reviewedMigrations = Object.freeze({
  [migrationPath]: migrationHash,
  [ivrMigrationPath]: ivrMigrationHash,
  [acwFormMigrationPath]: acwFormMigrationHash,
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
// The current candidate admits exactly three reviewed forward additions, never an arbitrary extra migration.
export function verifyReviewedMigrations(changes, readCurrent, schema) {
  const expected = Object.keys(reviewedMigrations).sort();
  const rows = changes.trim().split('\n').filter(Boolean).sort();
  if (JSON.stringify(rows) !== JSON.stringify(expected.map(path => `A\t${path}`))) {
    throw new Error('Only the three exact reviewed additions are admitted; historical migrations/schema/SQL remain protected.');
  }
  for (const path of expected) {
    const actual = createHash('sha256').update(readCurrent(path)).digest('hex');
    if (actual !== reviewedMigrations[path]) throw new Error(`Reviewed migration content changed: ${path}`);
  }
  return validateNewMigrationTimestamps(schema, expected);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const changes = execFileSync('git', ['diff', '--name-status', base, 'HEAD', '--', 'db/migrate', 'db/schema.rb', 'db/sql'], { encoding: 'utf8' });
  const schema = execFileSync('git', ['show', `${base}:db/schema.rb`], { encoding: 'utf8' });
  const result = verifyReviewedMigrations(changes, readFileSync, schema);
  console.log(JSON.stringify({ protectedBase: base, reviewedMigrations, ...result }));
}
