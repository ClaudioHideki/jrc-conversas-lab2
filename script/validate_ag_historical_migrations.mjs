import { createHash } from 'node:crypto';
import { validateNewMigrationTimestamps } from './validate_migration_timestamps.mjs';

// This is one audited historical import, not a configurable retroactivity bypass.
export const REVIEWED_BASE = 'd8a83b824b11cc68ddbbce7c79681f368051fb70';
export const REVIEWED_SOURCE = '4c8968de5d4762e88c87e8da5e28522a014f23fe';
const migrationPath = /^db\/migrate\/(\d{14})_[a-z0-9_]+\.rb$/;
const sqlPath = /^db\/functions\/\d{14}_[a-z0-9_]+\.sql$/;
const digest = source => createHash('sha256').update(source).digest('hex');
const sorted = values => [...values].sort();
const same = (left, right) => JSON.stringify(sorted(left)) === JSON.stringify(sorted(right));

export function validateHistoricalMigrationAdmission({
  baseSha, baseSchema, manifest, addedPaths, auditedAddedPaths,
  baseMigrationPaths, changedBasePaths, readCurrent, readAudited,
}) {
  const strict = validateNewMigrationTimestamps(baseSchema, []);
  if (baseSha !== REVIEWED_BASE || manifest.format_version !== 1 ||
      manifest.base_sha !== REVIEWED_BASE || manifest.audited_source_sha !== REVIEWED_SOURCE ||
      manifest.base_schema_sha256 !== digest(baseSchema)) {
    throw new Error('Historical admission requires the exact reviewed base, source and schema.');
  }
  if (changedBasePaths.length) throw new Error('Existing main migrations must remain unchanged.');
  const original = auditedAddedPaths.filter(name => migrationPath.test(name));
  const added = addedPaths.filter(name => migrationPath.test(name));
  const entries = manifest.migrations;
  if (!Array.isArray(entries) || !same(entries.map(item => item.path), original) ||
      new Set(entries.map(item => item.path)).size !== entries.length ||
      original.some(name => !added.includes(name))) {
    throw new Error('Historical admission inventory differs from the audited Git import.');
  }
  const versions = [...baseMigrationPaths, ...added].filter(name => migrationPath.test(name))
    .map(name => migrationPath.exec(name)[1]);
  if (new Set(versions).size !== versions.length) throw new Error('Migration version collision.');
  const historical = new Set();
  const dependencies = new Set();
  for (const entry of entries) {
    const version = migrationPath.exec(entry.path)?.[1];
    if (!version || entry.version !== version || entry.requires_execution !== true ||
        entry.historical !== (version <= strict.baseSchemaVersion)) {
      throw new Error('Invalid historical migration classification.');
    }
    const reviewed = readAudited(entry.path).toString();
    if (digest(reviewed) !== entry.sha256 || digest(readCurrent(entry.path)) !== entry.sha256) {
      throw new Error('Audited migration content changed: ' + entry.path);
    }
    const sql = [...new Set(reviewed.match(/db\/functions\/\d{14}_[a-z0-9_]+\.sql/g) || [])];
    if (!same(entry.sql_dependencies, sql)) throw new Error('Migration SQL dependencies changed.');
    sql.forEach(name => dependencies.add(name));
    for (const dependency of entry.depends_on) {
      if (!original.includes(dependency) || migrationPath.exec(dependency)[1] >= version) {
        throw new Error('Historical migration dependency order is invalid.');
      }
    }
    if (entry.historical) historical.add(entry.path);
  }
  if (!Array.isArray(manifest.sql_dependencies) ||
      !same(manifest.sql_dependencies.map(item => item.path), [...dependencies]) ||
      new Set(manifest.sql_dependencies.map(item => item.path)).size !== dependencies.size) {
    throw new Error('Historical SQL dependency inventory differs from the reviewed sources.');
  }
  for (const item of manifest.sql_dependencies) {
    if (!sqlPath.test(item.path) || digest(readAudited(item.path)) !== item.sha256 ||
        digest(readCurrent(item.path)) !== item.sha256) {
      throw new Error('Audited SQL dependency changed: ' + item.path);
    }
  }
  // Every unlisted migration still goes through the unchanged strict timestamp policy.
  const forward = validateNewMigrationTimestamps(baseSchema, added.filter(name => !historical.has(name)));
  return {
    baseSchemaVersion: strict.baseSchemaVersion, migrationCount: added.length,
    historicalCount: historical.size, forwardCount: forward.migrationCount,
  };
}
