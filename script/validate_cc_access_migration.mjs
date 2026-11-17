import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

export const migrationPath = 'db/migrate/20261117190000_add_contact_center_access_grants.rb';
export const migrationHash = 'c12bc8165b1641be2cd0b43d4c6e01d83067332a8fa0f4ce5d0f723c67a21932';
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

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const changes = execFileSync('git', ['diff', '--name-status', base, 'HEAD', '--', 'db/migrate', 'db/schema.rb', 'db/sql'], { encoding: 'utf8' });
  const schema = execFileSync('git', ['show', `${base}:db/schema.rb`], { encoding: 'utf8' });
  const result = verifyAccessMigration(changes, readFileSync(migrationPath), schema);
  console.log(JSON.stringify({ protectedBase: base, migrationPath, migrationHash, ...result }));
}
