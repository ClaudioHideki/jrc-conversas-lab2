import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';

// Static source admission only. Native PostgreSQL installation/upgrade/reload
// and behavior tests remain mandatory; a matching source hash is not their proof.
export const sourcePins = Object.freeze({
  migration: Object.freeze({
    path: 'db/migrate/20261123180000_create_contact_center_ending_execution_origins.rb',
    sha256: '38ef3d266c3f25a7ff53a8dc3e4259f93f1af9b51bb538cac90cfcc25227428c',
  }),
  sql: Object.freeze({
    path: 'db/functions/20261123180000_contact_center_ending_execution_origins.sql',
    sha256: 'e9e97c3db666a8b5a59ae4852786a342b1df8101105b8b9ce1415d71e5cf1ed6',
  }),
  receipt: Object.freeze({
    path: 'lib/jrc_contact_center/ending_execution_origin_schema_receipt.rb',
    sha256: '4ce75de6aae5a1446ad30f52a7a7285286c8a636b76bee20a99e17006fac3587',
  }),
});

export function validateEndingOriginSources(contents) {
  const expected = Object.keys(sourcePins).sort();
  if (JSON.stringify(Object.keys(contents).sort()) !== JSON.stringify(expected))
    throw new Error('Incomplete ending origin source identity');
  for (const [key, pin] of Object.entries(sourcePins)) {
    const raw = contents[key];
    if (!Buffer.isBuffer(raw) || raw.length < 1 || raw.length > 400_000)
      throw new Error('Invalid ending origin source boundary');
    if (crypto.createHash('sha256').update(raw).digest('hex') !== pin.sha256)
      throw new Error(`Ending origin source differs: ${pin.path}`);
  }
  const migration = contents.migration.toString('utf8');
  for (const key of ['sql', 'receipt']) {
    if (!migration.includes(sourcePins[key].sha256))
      throw new Error('Transitive ending origin source pin is missing');
  }
  return { static_only: true, source_identity_verified: true, native_schema_or_execution_accepted: false,
    paths: Object.values(sourcePins).map(pin => ({ ...pin })) };
}

export function readEndingOriginSources(root) {
  return Object.fromEntries(Object.entries(sourcePins).map(([key, pin]) => [key, fs.readFileSync(path.join(root, pin.path))]));
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  const root = process.argv[2] ? path.resolve(process.argv[2]) : process.cwd();
  console.log(JSON.stringify(validateEndingOriginSources(readEndingOriginSources(root))));
}
