import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Exact additive source identity only; native installation, upgrade, reload and
// prospective authorization/concurrency remain separate mandatory checks.
export const sourcePins = Object.freeze({
  "migration": {
    "path": "db/migrate/20261124001000_create_contact_center_ending_action_attempts.rb",
    "sha256": "a4e1893ac89f24823fa7779dc4bc7d625134677bcfddfd0f8eb1ca8a15aa0dc8"
  },
  "sql": {
    "path": "db/functions/20261124001000_contact_center_ending_attempts.sql",
    "sha256": "7c317f8dde21ef093a5c6ebe12b09f5b84fc65d253f61d5a01256e3e88e1f29f"
  },
  "receipt": {
    "path": "lib/jrc_contact_center/ending_action_attempt_schema_receipt.rb",
    "sha256": "d143e6d8b95c4af20047af63fb68fb8694492d6063f0a3ff2c14eb53ed0fdb6f"
  }
});
Object.values(sourcePins).forEach(pin => Object.freeze(pin));

export function validateEndingAttemptSources(contents) {
  if (JSON.stringify(Object.keys(contents).sort()) !== JSON.stringify(Object.keys(sourcePins).sort()))
    throw new Error('Incomplete ending attempt sources');
  for (const [key, pin] of Object.entries(sourcePins)) {
    const raw = contents[key];
    if (!Buffer.isBuffer(raw) || raw.length < 1 || raw.length > 400_000)
      throw new Error('Invalid ending attempt source boundary');
    if (crypto.createHash('sha256').update(raw).digest('hex') !== pin.sha256)
      throw new Error(`Ending attempt source differs: ${pin.path}`);
  }
  for (const key of ['sql', 'receipt']) {
    if (!contents.migration.toString('utf8').includes(sourcePins[key].sha256))
      throw new Error('Transitive attempt source pin is missing');
  }
  return { static_only: true, source_identity_verified: true, native_schema_or_execution_accepted: false };
}

export function readEndingAttemptSources(root) {
  return Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, fs.readFileSync(path.join(root, pin.path))]));
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  console.log(JSON.stringify(validateEndingAttemptSources(readEndingAttemptSources(process.argv[2] || process.cwd()))));
}
