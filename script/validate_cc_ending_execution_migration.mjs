import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Exact additive source identity only; native installation, upgrade, reload and
// prospective authorization/concurrency remain separate mandatory checks.
export const sourcePins = Object.freeze({
  "migration": {
    "path": "db/migrate/20261124000000_create_contact_center_ending_action_executions.rb",
    "sha256": "9caa7bfad60f9da1afee9a57c32a8d0f0c84f644c051401772d986d083499585"
  },
  "sql": {
    "path": "db/functions/20261124000000_contact_center_ending_executions.sql",
    "sha256": "18f93d4daf3cd6210ca57a914787baf164867edb41f186c35169f167981bf675"
  },
  "receipt": {
    "path": "lib/jrc_contact_center/ending_action_execution_schema_receipt.rb",
    "sha256": "28ffc5a421d7060f0aa0c1d916e97f4e4f0d7f09eed000ddbd2142727d4d8e16"
  }
});
Object.values(sourcePins).forEach(pin => Object.freeze(pin));

export function validateEndingExecutionSources(contents) {
  if (JSON.stringify(Object.keys(contents).sort()) !== JSON.stringify(Object.keys(sourcePins).sort()))
    throw new Error('Incomplete ending execution sources');
  for (const [key, pin] of Object.entries(sourcePins)) {
    const raw = contents[key];
    if (!Buffer.isBuffer(raw) || raw.length < 1 || raw.length > 400_000)
      throw new Error('Invalid ending execution source boundary');
    if (crypto.createHash('sha256').update(raw).digest('hex') !== pin.sha256)
      throw new Error(`Ending execution source differs: ${pin.path}`);
  }
  for (const key of ['sql', 'receipt']) {
    if (!contents.migration.toString('utf8').includes(sourcePins[key].sha256))
      throw new Error('Transitive execution source pin is missing');
  }
  return { static_only: true, source_identity_verified: true, native_schema_or_execution_accepted: false };
}

export function readEndingExecutionSources(root) {
  return Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, fs.readFileSync(path.join(root, pin.path))]));
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  console.log(JSON.stringify(validateEndingExecutionSources(readEndingExecutionSources(process.argv[2] || process.cwd()))));
}
