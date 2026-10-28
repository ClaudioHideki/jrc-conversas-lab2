const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const validation = process.env.HOTFIX_VALIDATION;
const root = process.env.HOTFIX_WORKSPACE;
const candidate = JSON.parse(fs.readFileSync(`${validation}/candidate.json`, 'utf8'));
const original = 'ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:40d8073e0861b156f344c1f4fb882e8472c9560149ef5a353d27a5a4b23fb2d1';
const docker = args => execFileSync('docker', args, { encoding: 'utf8', maxBuffer: 20000000 });
const inspect = image => JSON.parse(docker(['image', 'inspect', image]))[0];
const oldImage = inspect(original);
const newImage = inspect(candidate.image);
if (newImage.Config.Labels['org.opencontainers.image.revision'] !== candidate.revision) throw Error('Wrong image revision');
if (newImage.Os !== 'linux' || newImage.Architecture !== 'amd64') throw Error('Wrong platform');
if (JSON.stringify(oldImage.RootFS.Layers) !== JSON.stringify(newImage.RootFS.Layers.slice(0, oldImage.RootFS.Layers.length))) throw Error('Original layers changed');
for (const key of ['Env', 'Cmd', 'Entrypoint', 'WorkingDir', 'User', 'ExposedPorts', 'Volumes', 'Healthcheck']) {
  if (JSON.stringify(oldImage.Config[key]) !== JSON.stringify(newImage.Config[key])) throw Error(`Runtime setting changed: ${key}`);
}
const actual = JSON.parse(docker(['run', '--rm', '--network', 'none', '--read-only', '--mount', `type=bind,source=${validation}/image-source.rb,target=/image-source.rb,readonly`, '--entrypoint', 'ruby', candidate.image, '/image-source.rb']));
const oldActual = JSON.parse(docker(['run', '--rm', '--network', 'none', '--read-only', '--mount', `type=bind,source=${validation}/image-source.rb,target=/image-source.rb,readonly`, '--entrypoint', 'ruby', original, '/image-source.rb']));
const productDifferences = Object.keys(actual.hashes).filter(file => actual.hashes[file] !== oldActual.hashes[file]);
if (productDifferences.length !== candidate.files.length || productDifferences.some(p => !candidate.files.includes(p))) throw Error(`Unexpected product changes: ${productDifferences}`);
for (const file of candidate.files) {
  const expected = execFileSync('git', ['rev-parse', `${candidate.revision}:${file}`], { cwd: root, encoding: 'utf8' }).trim();
  if (actual.hashes[file] !== expected) throw Error(`Source mismatch: ${file}`);
}
if (actual.revision !== candidate.revision) throw Error('Wrong internal SHA');
const assetHashes = {};
const walk = dir => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const filename = `${dir}/${entry.name}`;
    if (entry.isDirectory()) walk(filename);
    else {
      const relative = filename.slice(`${candidate.context}/`.length);
      assetHashes[relative] = crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
    }
  }
};
walk(`${candidate.context}/public/vite`);
fs.writeFileSync(`${validation}/compiled-asset-hashes.json`, JSON.stringify(assetHashes));
const ruby = "require 'json'; require 'digest'; files=JSON.parse(File.read('/validation/compiled-asset-hashes.json')); files.each { |p,h| raise p unless Digest::SHA256.file('/app/'+p).hexdigest == h }; puts JSON.generate(verified_assets: files.size)";
const assets = JSON.parse(docker(['run', '--rm', '--network', 'none', '--read-only', '--mount', `type=bind,source=${validation},target=/validation,readonly`, '--entrypoint', 'ruby', candidate.image, '-e', ruby]));
const report = { revision: candidate.revision, image: candidate.image, platform: 'linux/amd64', originalLayersPreserved: oldImage.RootFS.Layers.length, runtimeSettingsPreserved: true, productDifferences, verifiedAssets: assets.verified_assets, imageId: newImage.Id };
fs.writeFileSync(`${validation}/candidate-verification.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
