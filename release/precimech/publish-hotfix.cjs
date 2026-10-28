const fs = require('node:fs');
const { execFileSync } = require('node:child_process');
const validation = process.env.HOTFIX_VALIDATION;
const root = process.env.HOTFIX_WORKSPACE;
const candidate = JSON.parse(fs.readFileSync(`${validation}/candidate.json`, 'utf8'));
const verified = JSON.parse(fs.readFileSync(`${validation}/candidate-verification.json`, 'utf8'));
const backend = JSON.parse(fs.readFileSync(`${validation}/backend-hotfix-image.json`, 'utf8'));
if (verified.revision !== candidate.revision || backend.passed !== 8) throw Error('Candidate validation incomplete');
const docker = args => execFileSync('docker', args, { encoding: 'utf8', maxBuffer: 20000000 });
const local = JSON.parse(docker(['image', 'inspect', candidate.image]))[0];
if (local.Id !== verified.imageId) throw Error('Local candidate changed after validation');
const remoteBranch = execFileSync('git', ['ls-remote', 'origin', 'refs/heads/codex/precimech-contatos-hotfix-20261028'], { cwd: root, encoding: 'utf8' });
if (remoteBranch.split(/\s+/)[0] !== candidate.revision) throw Error('Remote source SHA mismatch');
let absent = false;
try {
  docker(['buildx', 'imagetools', 'inspect', candidate.image]);
} catch (error) {
  const message = String(error.stderr || '');
  if (/not found|manifest unknown/i.test(message) && !/unauthorized|denied|forbidden/i.test(message)) absent = true;
  else throw error;
}
if (!absent) throw Error('Refusing to overwrite an existing registry tag');
const pushOutput = docker(['push', candidate.image]);
fs.writeFileSync(`${validation}/registry-push.log`, pushOutput);
const digest = docker(['buildx', 'imagetools', 'inspect', candidate.image, '--format', '{{.Manifest.Digest}}']).trim();
if (!/^sha256:[0-9a-f]{64}$/.test(digest)) throw Error('Registry did not return a valid digest');
const repository = candidate.image.slice(0, candidate.image.lastIndexOf(':'));
const pinned = `${repository}@${digest}`;
const manifestBytes = execFileSync('docker', ['buildx', 'imagetools', 'inspect', pinned, '--raw'], { maxBuffer: 20000000 });
const manifest = JSON.parse(manifestBytes.toString('utf8'));
// Inspect the registry's config object as well as its immutable manifest identity.
if (manifest.config.digest !== local.Id && digest !== local.Id) throw Error('Published image identity differs from the tested candidate');
const remote = JSON.parse(docker(['buildx', 'imagetools', 'inspect', pinned, '--format', '{{json .Image}}']));
if (remote.config.Labels['org.opencontainers.image.revision'] !== candidate.revision) throw Error('Published revision mismatch');
const result = { image: candidate.image, revision: candidate.revision, digest, pinned, imageId: local.Id, verifiedAt: new Date().toISOString(), deployed: false };
fs.writeFileSync(`${validation}/publication.json`, JSON.stringify(result, null, 2));
console.log(JSON.stringify(result, null, 2));
