import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Exact additive source identity only; native installation, upgrade, reload and
// prospective authorization/concurrency remain separate mandatory checks.
export const sourcePins = Object.freeze({
  "migration": {
    "path": "db/migrate/20261126193000_create_contact_center_quality_reviews.rb",
    "sha256": "ab708f3b36ac763af666d7b871b53ece2b77cf27b87359d2bf71909b4bda3123"
  },
  "sql": {
    "path": "db/functions/20261126193000_contact_center_quality_reviews.sql",
    "sha256": "c6f65980ef4ce034b19ebcc4974f251249ac935092be01b613621ef0bd84e19b"
  },
  "receipt": {
    "path": "lib/jrc_contact_center/quality_review_schema_receipt.rb",
    "sha256": "b126ee6710363470983ca0717d2ae97ab4fca97501fd31b66d7ab0d068378a29"
  }
});
Object.values(sourcePins).forEach(pin => Object.freeze(pin));

export function validateQualityReviewSources(contents) {
  if (JSON.stringify(Object.keys(contents).sort()) !== JSON.stringify(Object.keys(sourcePins).sort()))
    throw new Error('Incomplete quality review sources');
  for (const [key, pin] of Object.entries(sourcePins)) {
    const raw = contents[key];
    if (!Buffer.isBuffer(raw) || raw.length < 1 || raw.length > 400_000)
      throw new Error('Invalid quality review source boundary');
    if (crypto.createHash('sha256').update(raw).digest('hex') !== pin.sha256)
      throw new Error(`Quality review source differs: ${pin.path}`);
  }
  for (const key of ['sql', 'receipt']) {
    if (!contents.migration.toString('utf8').includes(sourcePins[key].sha256))
      throw new Error('Transitive quality review source pin is missing');
  }
  return { static_only: true, source_identity_verified: true, native_schema_or_execution_accepted: false };
}

export function readQualityReviewSources(root) {
  return Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, fs.readFileSync(path.join(root, pin.path))]));
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  console.log(JSON.stringify(validateQualityReviewSources(readQualityReviewSources(process.argv[2] || process.cwd()))));
}
