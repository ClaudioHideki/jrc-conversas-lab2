import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { parse, compileScript, compileTemplate } from '@vue/compiler-sfc';

const base = process.argv[2];
if (!base) throw new Error('Provide the reviewed base revision.');
const changed = new Set([
  ...execFileSync('git', ['diff', '--name-only', '--diff-filter=ACMR', base, '--']).toString().trim().split('\n'),
  ...execFileSync('git', ['ls-files', '--others', '--exclude-standard']).toString().trim().split('\n'),
]);
let count = 0;
for (const filename of [...changed].filter(Boolean)) {
  if (!/\.(json|js|mjs|vue)$/.test(filename)) continue;
  const source = fs.readFileSync(filename, 'utf8');
  if (filename.endsWith('.json')) {
    JSON.parse(source);
  } else if (filename.endsWith('.vue')) {
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
