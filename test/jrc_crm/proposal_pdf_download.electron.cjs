// Run with desktop/node_modules/electron/dist/electron.exe, not the installer.
// No production profile, server, credentials, or SIP is loaded.
const { app, BrowserWindow } = require('electron');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const os = require('node:os');
const { trustedUrl } = require('../../desktop/src/policy.cjs');

const output = fs.mkdtempSync(path.join(os.tmpdir(), 'jrc-pdf-test-'));
app.setPath('userData', output);
const source = fs.readFileSync(
  path.join(
    __dirname,
    '../../app/javascript/dashboard/routes/dashboard/crm/views/proposals/ProposalsIndex.vue'
  ),
  'utf8'
);
// Execute the actual component download action in Chromium, without mounting the app.
const action = source.slice(
  source.indexOf('const downloadPdf ='),
  source.indexOf('const copyPublicLink =')
);
assert.ok(action.includes('URL.createObjectURL'));
const payload = Buffer.from('%PDF-1.4\n% isolated download test\n%%EOF');
let authorized = false;
let opened = false;
let navigated = false;
let window;
const server = http.createServer((req, res) => {
  if (req.url === '/pdf') {
    authorized = req.headers['x-test-auth'] === 'local-test';
    res.writeHead(authorized ? 200 : 401, {
      'Content-Type': 'application/pdf',
    });
    res.end(payload);
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end('<!doctype html><title>Isolated PDF test</title>');
});
const timeout = setTimeout(() => {
  process.stderr.write('FAIL: download timeout\n');
  app.exit(1);
}, 30000);

app
  .whenReady()
  .then(async () => {
    await new Promise(resolve => {
      server.listen(0, '127.0.0.1', resolve);
    });
    const origin = `http://127.0.0.1:${server.address().port}`;
    window = new BrowserWindow({
      show: false,
      webPreferences: {
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    });
    window.webContents.setWindowOpenHandler(() => {
      opened = true;
      return { action: 'deny' };
    });
    window.webContents.on('will-navigate', (event, url) => {
      navigated = true;
      if (!trustedUrl(event.url || url, origin)) event.preventDefault();
    });
    window.webContents.session.on('will-download', (_event, item) => {
      const destination = path.join(output, 'download.pdf');
      item.setSavePath(destination);
      item.once('done', (_doneEvent, state) => {
        try {
          assert.equal(state, 'completed');
          assert.deepEqual(fs.readFileSync(destination), payload);
          assert.equal(authorized, true);
          assert.equal(opened, false);
          assert.equal(navigated, false);
          assert.equal(window.webContents.getURL(), origin + '/');
          process.stdout.write(
            'PASS: actual Vue download action saved authenticated blob; no new window/navigation; isolation preserved.'
          );
          clearTimeout(timeout);
          server.close();
          app.exit(0);
        } catch (error) {
          process.stderr.write(String(error.stack));
          app.exit(1);
        }
      });
    });
    await window.loadURL(origin);
    await window.webContents.executeJavaScript(`
    const selectedProposal = {value: {id: 1, version_number: 3}};
    const pdfLoading = {value: false}, loadingDetails = {value: false}, saving = {value: false}, itemSaving = {value: false};
    const hasUnsavedChanges = {value: false}, hasPendingItem = {value: false}, itemUpdateFailed = {value: false};
    const useAlert = message => { throw new Error(message); }, t = key => key;
    const proposalsAPI = {pdf: async () => ({data: await (await fetch('/pdf', {headers: {'X-Test-Auth':'local-test'}})).blob()})};
    ${action}
    downloadPdf();
  `);
  })
  .catch(error => {
    process.stderr.write(String(error.stack));
    app.exit(1);
  });
