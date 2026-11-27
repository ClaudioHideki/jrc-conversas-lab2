import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Exact additive source identity only; native installation, upgrade, reload and
// prospective authorization/concurrency remain separate mandatory checks.
export const sourcePins = Object.freeze({
  "migration": {
    "path": "db/migrate/20261127003000_create_contact_center_recording_task_links.rb",
    "sha256": "21594036dd147d4f903c74de0c37e2951eee6fe1473fc2ea433ca3037c1bc519"
  },
  "sql": {
    "path": "db/functions/20261127003000_contact_center_recording_task_links.sql",
    "sha256": "7f013d1a932a7832e56b34f02d1d0cd12b4d961c6663922d64817a5c6ff7c238"
  },
  "receipt": {
    "path": "lib/jrc_contact_center/recording_task_schema_receipt.rb",
    "sha256": "e33b56fa7770ec904672061f1bf27e4f47b89b906a84cc8f73d9320a08e60537"
  }
});
Object.values(sourcePins).forEach(pin => Object.freeze(pin));

export function validateRecordingTaskSources(contents) {
  if (JSON.stringify(Object.keys(contents).sort()) !== JSON.stringify(Object.keys(sourcePins).sort()))
    throw new Error('Incomplete recording task sources');
  for (const [key, pin] of Object.entries(sourcePins)) {
    const raw = contents[key];
    if (!Buffer.isBuffer(raw) || raw.length < 1 || raw.length > 400_000)
      throw new Error('Invalid recording task source boundary');
    if (crypto.createHash('sha256').update(raw).digest('hex') !== pin.sha256)
      throw new Error(`Recording task source differs: ${pin.path}`);
  }
  for (const key of ['sql', 'receipt']) {
    if (!contents.migration.toString('utf8').includes(sourcePins[key].sha256))
      throw new Error('Transitive recording task source pin is missing');
  }
  return { static_only: true, source_identity_verified: true, native_schema_or_execution_accepted: false };
}

export function readRecordingTaskSources(root) {
  return Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, fs.readFileSync(path.join(root, pin.path))]));
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  console.log(JSON.stringify(validateRecordingTaskSources(readRecordingTaskSources(process.argv[2] || process.cwd()))));
}
