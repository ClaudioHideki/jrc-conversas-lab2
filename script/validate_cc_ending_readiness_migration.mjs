import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Exact additive source identity only; native installation, upgrade, reload and
// prospective authorization/concurrency remain separate mandatory checks.
export const sourcePins = Object.freeze({
  "migration": {
    "path": "db/migrate/20261123235000_create_contact_center_ending_action_readinesses.rb",
    "sha256": "7980d4b64320f602b9edfee3083c14134c86f2784e0275611556bb26e17fd59f"
  },
  "sql": {
    "path": "db/functions/20261123235000_contact_center_ending_action_readiness.sql",
    "sha256": "13a6da4ca25eb6dd7f826a39070ebabb381fc776934f098504e1020c8d24d4e7"
  },
  "receipt": {
    "path": "lib/jrc_contact_center/ending_action_readiness_schema_receipt.rb",
    "sha256": "7dd62dafddbab0a574c9e89337df6629b2bafcd6700d6e0a56bdb28adfd7bce2"
  }
});
Object.values(sourcePins).forEach(pin => Object.freeze(pin));

export function validateEndingReadinessSources(contents) {
  if (JSON.stringify(Object.keys(contents).sort()) !== JSON.stringify(Object.keys(sourcePins).sort()))
    throw new Error('Incomplete ending readiness sources');
  for (const [key, pin] of Object.entries(sourcePins)) {
    const raw = contents[key];
    if (!Buffer.isBuffer(raw) || raw.length < 1 || raw.length > 400_000)
      throw new Error('Invalid ending readiness source boundary');
    if (crypto.createHash('sha256').update(raw).digest('hex') !== pin.sha256)
      throw new Error(`Ending readiness source differs: ${pin.path}`);
  }
  for (const key of ['sql', 'receipt']) {
    if (!contents.migration.toString('utf8').includes(sourcePins[key].sha256))
      throw new Error('Transitive readiness source pin is missing');
  }
  return { static_only: true, source_identity_verified: true, native_schema_or_execution_accepted: false };
}

export function readEndingReadinessSources(root) {
  return Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, fs.readFileSync(path.join(root, pin.path))]));
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  console.log(JSON.stringify(validateEndingReadinessSources(readEndingReadinessSources(process.argv[2] || process.cwd()))));
}
