export function validateNewMigrationTimestamps(baseSchemaSource, newPaths) {
  const match = /ActiveRecord::Schema(?:\[[^\]]+\])?\.define\(\s*version:\s*([\d_]+)\s*\)/.exec(baseSchemaSource);
  const baseSchemaVersion = match?.[1].replaceAll('_', '');
  if (!baseSchemaVersion || !/^\d{14}$/.test(baseSchemaVersion)) {
    throw new Error('Cannot read the reviewed base schema version.');
  }
  const migrations = [...new Set(newPaths)].map(filename => {
    const timestamp = /^db\/migrate\/(\d{14})_[^/]+\.rb$/.exec(filename.replaceAll('\\', '/'))?.[1];
    return timestamp ? { filename, timestamp } : null;
  }).filter(Boolean);
  for (const { filename, timestamp } of migrations) {
    if (timestamp <= baseSchemaVersion) {
      throw new Error(`New migration ${filename} must sort after the reviewed base schema version ${baseSchemaVersion}.`);
    }
  }
  return { baseSchemaVersion, migrationCount: migrations.length };
}
