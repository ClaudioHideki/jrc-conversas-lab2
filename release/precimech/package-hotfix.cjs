const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const root = process.env.HOTFIX_WORKSPACE;
const validation = process.env.HOTFIX_VALIDATION;
const base = '4ce8241d35ce862e9d53e9a5dce4df9a1858432c';
const git = args => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
const revision = git(['rev-parse', 'HEAD']);
if (!/^[0-9a-f]{40}$/.test(revision) || revision === base) throw Error('Expected a new full hotfix SHA');
if (git(['rev-parse', 'HEAD^']) !== base) throw Error('Hotfix must be based directly on the validated original');
if (git(['status', '--porcelain'])) throw Error('Hotfix source must be clean');
const files = [
  'app/controllers/api/v1/accounts/contacts_controller.rb',
  'app/models/contact.rb',
  'config/locales/en.yml',
  'app/javascript/dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue',
  'app/javascript/dashboard/routes/dashboard/contacts/pages/ContactsIndex.vue',
  'app/javascript/dashboard/store/modules/contacts/actions.js',
  'app/javascript/dashboard/store/modules/contacts/mutations.js',
];
const runtimeChanges = git(['diff', '--name-only', base, revision, '--', 'app', 'config', 'db', 'lib', 'enterprise', 'public', 'Gemfile', 'Gemfile.lock', 'package.json', 'pnpm-lock.yaml', 'services']).split('\n').filter(p => !p.includes('/spec/') && !p.includes('/specs/'));
if (runtimeChanges.length !== files.length || runtimeChanges.some(p => !files.includes(p))) throw Error('Unexpected product scope');
const context = `${validation}/build-context`;
fs.mkdirSync(context);
for (const file of [...files, 'docker/precimech-hotfix.Dockerfile']) {
  const destination = path.join(context, file);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, execFileSync('git', ['show', `${revision}:${file}`], { cwd: root }));
}
const assets = `${root}/public/vite`;
if (!fs.existsSync(`${assets}/.vite/manifest.json`)) throw Error('Production Vite manifest missing');
fs.cpSync(assets, `${context}/public/vite`, { recursive: true });
const manifest = JSON.parse(fs.readFileSync(`${assets}/.vite/manifest.json`, 'utf8'));
for (const item of Object.values(manifest)) {
  for (const file of [item.file, ...(item.css || []), ...(item.assets || [])].filter(Boolean)) {
    if (!fs.existsSync(`${assets}/${file}`)) throw Error(`Compiled asset missing: ${file}`);
  }
}
const image = `ghcr.io/claudiohideki/jrc-conversas-lab2:precimech-contatos-sha-${revision}`;
const result = { revision, base, image, context, files, manifestEntries: Object.keys(manifest).length };
fs.writeFileSync(`${validation}/candidate.json`, JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
