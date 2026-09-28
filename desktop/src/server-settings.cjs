const path = require('node:path');
const { serverOrigin } = require('./policy.cjs');

// Stable across development, packaged builds and product-name changes.
// Electron resolves appData for the current OS/user; never use a user-specific path.
function serverSettings(app, fileSystem) {
  const directory = path.join(app.getPath('appData'), 'JRC Softphone');
  fileSystem.mkdirSync(directory, { recursive: true });
  app.setPath('userData', directory);
  const file = path.join(app.getPath('userData'), 'softphone-server.json');
  return {
    read() {
      try {
        const saved = JSON.parse(fileSystem.readFileSync(file, 'utf8'));
        return serverOrigin(saved.origin);
      } catch (error) {
        if (error.code === 'ENOENT') return undefined;
        throw new Error(
          'Não foi possível ler o servidor salvo. Configure o endereço novamente.'
        );
      }
    },
    save(value) {
      const origin = serverOrigin(value);
      // Atomic replacement leaves the previous valid configuration intact on failure.
      fileSystem.writeFileSync(`${file}.tmp`, JSON.stringify({ origin }), {
        encoding: 'utf8',
        mode: 0o600,
      });
      fileSystem.renameSync(`${file}.tmp`, file);
    },
  };
}

module.exports = { serverSettings };
