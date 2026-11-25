import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Exact additive source identity only; native installation, upgrade, reload and
// prospective authorization/concurrency remain separate mandatory checks.
export const sourcePins = Object.freeze({
  "migration": {
    "path": "db/migrate/20261125060000_create_contact_center_typed_destinations.rb",
    "sha256": "e7b2540684d6bf4a215c28f73e6db561abd25178c2533ebeb9702eb631a85c00"
  },
  "sql": {
    "path": "db/functions/20261125060000_contact_center_typed_destinations.sql",
    "sha256": "2a1512a700604017b5f62b05d02e7152eb4335e61785775e041ba5bcca142940"
  },
  "receipt": {
    "path": "lib/jrc_contact_center/ending_destination_schema_receipt.rb",
    "sha256": "9c2a53008b9b7ce7935419d2845d65a0fc91fd6b2624ed4ff23253868a0a52ae"
  }
});
Object.values(sourcePins).forEach(pin => Object.freeze(pin));

export function validateTypedDestinationSources(contents) {
  if (JSON.stringify(Object.keys(contents).sort()) !== JSON.stringify(Object.keys(sourcePins).sort()))
    throw new Error('Incomplete typed destination sources');
  for (const [key, pin] of Object.entries(sourcePins)) {
    const raw = contents[key];
    if (!Buffer.isBuffer(raw) || raw.length < 1 || raw.length > 400_000)
      throw new Error('Invalid typed destination source boundary');
    if (crypto.createHash('sha256').update(raw).digest('hex') !== pin.sha256)
      throw new Error(`Typed destination source differs: ${pin.path}`);
  }
  for (const key of ['sql', 'receipt']) {
    if (!contents.migration.toString('utf8').includes(sourcePins[key].sha256))
      throw new Error('Transitive typed destination source pin is missing');
  }
  return { static_only: true, source_identity_verified: true, native_schema_or_execution_accepted: false };
}

export function readTypedDestinationSources(root) {
  return Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, fs.readFileSync(path.join(root, pin.path))]));
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  console.log(JSON.stringify(validateTypedDestinationSources(readTypedDestinationSources(process.argv[2] || process.cwd()))));
}
