import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

// A version recorded in schema_migrations cannot identify two different SQL histories.
// Report the conflict; never rename or mark either history as applied automatically.
export function inspectMigrationIdentities(names) {
  const byVersion = new Map();
  for (const name of names) {
    const match = /^(\d{14})_[a-z0-9_]+\.rb$/.exec(name);
    if (!match) throw new Error(`Invalid migration filename: ${name}`);
    const entries = byVersion.get(match[1]) || [];
    entries.push(name);
    byVersion.set(match[1], entries);
  }
  return [...byVersion.entries()]
    .filter(([, entries]) => entries.length > 1)
    .map(([version, files]) => ({ version, files: [...files].sort() }))
    .sort((a, b) => a.version.localeCompare(b.version));
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const folder = path.resolve('db/migrate');
  const files = fs.readdirSync(folder).filter(name => name.endsWith('.rb'));
  const collisions = inspectMigrationIdentities(files);
  console.log(JSON.stringify({ migrationCount: files.length, collisions }, null, 2));
  if (collisions.length) process.exitCode = 1;
}
