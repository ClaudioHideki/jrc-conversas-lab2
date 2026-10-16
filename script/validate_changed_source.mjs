import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

const base = process.argv[2];
if (!base) throw new Error('Provide the reviewed base revision.');
const untracked = execFileSync('git', ['ls-files', '--others', '--exclude-standard']).toString().trim().split('\n');
const changed = new Set([
  ...execFileSync('git', ['diff', '--name-only', '--diff-filter=ACMR', base, '--']).toString().trim().split('\n'),
  ...untracked,
]);
const addedMigrations = new Set([
  ...execFileSync('git', ['diff', '--no-renames', '--name-only', '--diff-filter=A', base, '--', 'db/migrate']).toString().trim().split('\n'),
  ...untracked,
]);
const baseSchema = execFileSync('git', ['show', `${base}:db/schema.rb`]).toString();
const migrationPolicy = validateNewMigrationTimestamps(baseSchema, [...addedMigrations].filter(Boolean));
let count = 0;
for (const filename of [...changed].filter(Boolean)) {
  if (!/\.(json|js|mjs|vue)$/.test(filename)) continue;
  const source = fs.readFileSync(filename, 'utf8');
  if (filename.endsWith('.json')) {
    JSON.parse(source);
  } else if (filename.endsWith('.vue')) {
    const { parse, compileScript, compileTemplate } = await import('@vue/compiler-sfc');
    const { descriptor, errors } = parse(source, { filename });
    if (errors.length) throw new Error(`${filename}: ${errors.join(', ')}`);
    if (descriptor.script || descriptor.scriptSetup) compileScript(descriptor, { id: filename });
    if (descriptor.template) {
      const template = compileTemplate({ source: descriptor.template.content, filename, id: filename });
      if (template.errors.length) throw new Error(`${filename}: ${template.errors.join(', ')}`);
    }
  } else {
    execFileSync(process.execPath, ['--input-type=module', '--check'], { input: source });
  }
  count += 1;
  console.log(`PASS ${filename}`);
}
const timestamps = fs.readdirSync('db/migrate').filter(name => /^\d{14}_.*\.rb$/.test(name)).map(name => name.slice(0, 14));
if (timestamps.length !== new Set(timestamps).size) throw new Error('Duplicate migration timestamp.');
console.log(`Validated ${count} changed sources and ${timestamps.length} migration timestamps.`);
console.log(`Validated ${migrationPolicy.migrationCount} new migrations after base schema ${migrationPolicy.baseSchemaVersion}.`);
