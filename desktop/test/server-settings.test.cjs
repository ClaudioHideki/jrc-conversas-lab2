/* eslint no-script-url: off */
const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const { harness } = require('./electronHarness.cjs');
const { serverOrigin } = require('../src/policy.cjs');

const ready = () =>
  new Promise(resolve => {
    setImmediate(resolve);
  });
const eventFor = win => ({
  sender: win.webContents,
  senderFrame: win.webContents.mainFrame,
});
const openSettings = h => {
  h.app.tray.menu
    .find(item => item.label === 'Configurações / Alterar servidor JRC')
    .click();
  return h.windows.at(-1);
};

test('first execution without a server opens only the isolated local setup, with no saved URL', async () => {
  const h = harness({ argv: [] });
  await ready();
  assert.equal(h.windows.length, 1);
  const setup = h.windows[0];
  assert.match(setup.loadedFile, /setup[\\/]index.html$/);
  assert.equal(setup.loadedUrl, undefined);
  assert.equal(setup.options.webPreferences.nodeIntegration, false);
  assert.equal(setup.options.webPreferences.contextIsolation, true);
  assert.equal(setup.options.webPreferences.sandbox, true);
  assert.match(setup.options.webPreferences.preload, /setup-preload.cjs$/);
  assert.equal(setup.checkPermission(), false);
  assert.equal(h.files.size, 0);
  assert.equal(h.app.quits, 0);
  assert.deepEqual(h.ipcMain['softphone:server-settings'](eventFor(setup)), {
    origin: '',
    error: '',
  });
  assert.equal(
    h.app.getPath('userData'),
    path.join(h.app.getPath('appData'), 'JRC Softphone')
  );
  assert.deepEqual(h.reads, [h.configPath]);
});

test('HTTPS provisioning normalizes to an origin and atomically persists no path, query or secrets', async () => {
  const h = harness({ argv: [] });
  await ready();
  const result = await h.ipcMain['softphone:set-server'](
    eventFor(h.windows[0]),
    { url: '  HTTPS://CLIENT.EXAMPLE:443/app/login?token=discard#discard  ' }
  );
  assert.deepEqual(result, { ok: true });
  assert.equal(h.windows[1].loadedUrl, 'https://client.example');
  assert.deepEqual(h.saved, [{ origin: 'https://client.example' }]);
  assert.equal(h.files.size, 1);
  assert.equal(
    h.files.get(h.configPath),
    '{"origin":"https://client.example"}'
  );
  assert.equal(h.windows[0].actions.at(-1), 'hide');
});

test('restart uses only canonical saved origin despite stale CLI/env or a second legacy config', async () => {
  const first = harness({ argv: [] });
  await ready();
  await first.ipcMain['softphone:set-server'](eventFor(first.windows[0]), {
    url: 'https://client.example:8443/app',
  });
  const legacy = path.join(
    first.app.getPath('appData'),
    'jrc-softphone-desktop',
    'softphone-server.json'
  );
  first.files.set(legacy, '{"origin":"https://legacy.example"}');
  const restarted = harness({
    files: first.files,
    env: { JRC_SOFTPHONE_URL: 'https://stale.example' },
  });
  await ready();
  assert.equal(restarted.windows[0].loadedUrl, 'https://client.example:8443');
  assert.deepEqual(restarted.reads, [restarted.configPath]);
  restarted.app.tray.menu
    .find(item => item.type === 'checkbox')
    .click({ checked: true });
  assert.deepEqual(restarted.app.loginSettings.args, []);
  assert.equal(
    restarted.files.get(legacy),
    '{"origin":"https://legacy.example"}'
  );
});

test('legacy enabled autostart loses its URL argument and keeps using the canonical origin', async () => {
  const h = harness({
    savedOrigin: 'https://saved.example',
    legacyAutostart: true,
  });
  await ready();
  assert.equal(h.windows[0].loadedUrl, 'https://saved.example');
  assert.equal(h.app.loginSettings.openAtLogin, true);
  assert.deepEqual(h.app.loginSettings.args, []);
});

test('missing canonical config does not silently read another directory', async () => {
  const files = new Map([
    [
      path.resolve(
        '/mock-app-data/jrc-softphone-desktop/softphone-server.json'
      ),
      '{"origin":"https://legacy.example"}',
    ],
  ]);
  const h = harness({ argv: [], files });
  await ready();
  assert.equal(h.windows[0].loadedUrl, undefined);
  assert.deepEqual(h.reads, [h.configPath]);
});

[
  'http://client.example',
  'https://user:password@client.example',
  'https://@client.example',
  'not a url',
  '',
  'file:///server',
  'javascript:alert(1)',
  'https:client.example',
  'https://bad_host.example',
  'https://client.example\\evil',
  'https://client.example\n.evil',
].forEach(url => {
  test(`provisioning rejects invalid/unsafe URL ${JSON.stringify(url)}`, async () => {
    assert.throws(() => serverOrigin(url));
    const h = harness({ argv: [] });
    await ready();
    const result = await h.ipcMain['softphone:set-server'](
      eventFor(h.windows[0]),
      { url }
    );
    assert.equal(result.ok, false);
    assert.equal(h.saved.length, 0);
    assert.equal(h.windows.length, 1);
  });
});

test('malformed saved JSON opens setup and can be replaced without fallback or app exit', async () => {
  const h = harness({ savedText: '{invalid' });
  await ready();
  assert.match(h.windows[0].loadedFile, /setup[\\/]index.html$/);
  assert.ok(
    h.ipcMain['softphone:server-settings'](eventFor(h.windows[0])).error
  );
  assert.equal(h.app.quits, 0);
  assert.equal(
    (
      await h.ipcMain['softphone:set-server'](eventFor(h.windows[0]), {
        url: 'https://client.example',
      })
    ).ok,
    true
  );
});

test('settings IPC cannot be invoked by remote JRC, floating, or another local frame', async () => {
  const h = harness();
  await ready();
  const setup = openSettings(h);
  const badFrames = [
    eventFor(h.windows[0]),
    {
      ...eventFor(setup),
      senderFrame: { url: setup.webContents.mainFrame.url },
    },
  ];
  await Promise.all(
    badFrames.map(async event => {
      assert.equal(h.ipcMain['softphone:server-settings'](event), null);
      assert.equal(
        (
          await h.ipcMain['softphone:set-server'](event, {
            url: 'https://other.example',
          })
        ).ok,
        false
      );
    })
  );
  assert.equal(h.windows[0].loadedUrl, 'https://jrc.example');
  assert.equal(h.saved.length, 1);
});

test('switch waits for shutdown ACK, destroys old renderer, clears session then saves/loads new server', async () => {
  const h = harness();
  await ready();
  const previous = h.windows[0];
  const setup = openSettings(h);
  h.lifecycle.length = 0;
  const pending = h.ipcMain['softphone:set-server'](eventFor(setup), {
    url: 'https://other.example/app',
  });
  assert.deepEqual(previous.webContents.sent.at(-1), [
    'softphone:floating-command',
    { action: 'shutdown' },
  ]);
  assert.equal(h.windows.length, 2);
  assert.equal(h.saved.length, 1);
  assert.equal(previous.isDestroyed(), false);
  assert.equal(
    (
      await h.ipcMain['softphone:set-server'](eventFor(setup), {
        url: 'https://concurrent.example',
      })
    ).ok,
    false
  );
  h.ipcMain.emit('softphone:floating-shutdown-complete', eventFor(previous));
  assert.equal((await pending).ok, true);
  assert.equal(h.app.exits, undefined);
  assert.equal(h.app.quits, 0);
  assert.equal(previous.isDestroyed(), true);
  assert.deepEqual(h.lifecycle, [
    'destroy:0',
    'closeConnections',
    'clearStorage',
    'clearAuth',
    'clearCache',
    'save',
    'load:https://other.example',
  ]);
  assert.equal(h.windows[2].loadedUrl, 'https://other.example');
  assert.equal(h.pendingTimers.size, 0);
});

test('no bridge/timeout forces old renderer termination before any new server can load', async () => {
  const h = harness();
  await ready();
  const setup = openSettings(h);
  const pending = h.ipcMain['softphone:set-server'](eventFor(setup), {
    url: 'https://other.example',
  });
  const [id, timer] = [...h.pendingTimers.entries()].find(
    ([, value]) => value.delay === 3000
  );
  h.pendingTimers.delete(id);
  timer.callback();
  assert.equal((await pending).ok, true);
  assert.equal(h.windows[0].isDestroyed(), true);
  assert.ok(
    h.lifecycle.indexOf('destroy:0') <
      h.lifecycle.indexOf('load:https://other.example')
  );
  assert.equal(h.app.quits, 0);
});

test('failed session cleanup blocks loading or persisting new environment', async () => {
  const h = harness({ failCleanup: true });
  await ready();
  const previous = h.windows[0];
  const setup = openSettings(h);
  const pending = h.ipcMain['softphone:set-server'](eventFor(setup), {
    url: 'https://other.example',
  });
  h.ipcMain.emit('softphone:floating-shutdown-complete', eventFor(previous));
  assert.equal((await pending).ok, false);
  assert.equal(previous.isDestroyed(), true);
  assert.equal(h.windows.length, 2);
  assert.equal(h.files.get(h.configPath), '{"origin":"https://jrc.example"}');
  h.app.tray.menu.find(item => item.label === 'Abrir Softphone').click();
  assert.equal(h.windows.length, 2);
  assert.equal(setup.actions.at(-1), 'focus');
  previous.webContents.session.clearStorageData = async () => {};
  assert.equal(
    (
      await h.ipcMain['softphone:set-server'](eventFor(setup), {
        url: 'https://other.example',
      })
    ).ok,
    true
  );
  assert.equal(h.windows[2].loadedUrl, 'https://other.example');
});

test('failed persistence never launches an unsaved server and does not expose raw errors', async () => {
  const h = harness({ argv: [], failSave: true });
  await ready();
  const result = await h.ipcMain['softphone:set-server'](
    eventFor(h.windows[0]),
    { url: 'https://client.example' }
  );
  assert.equal(result.ok, false);
  assert.equal(h.windows.length, 1);
  assert.equal(h.files.size, 0);
  assert.doesNotMatch(result.error, /write denied/);
});

test('selecting current server leaves its renderer/SIP intact; unsolicited shutdown ACK does not exit', async () => {
  const h = harness();
  await ready();
  const main = h.windows[0];
  const setup = openSettings(h);
  assert.equal(
    (
      await h.ipcMain['softphone:set-server'](eventFor(setup), {
        url: 'https://jrc.example/app',
      })
    ).ok,
    true
  );
  assert.equal(main.isDestroyed(), false);
  assert.equal(main.webContents.sent, undefined);
  h.ipcMain.emit('softphone:floating-shutdown-complete', eventFor(main));
  assert.equal(h.app.exits, undefined);
});

test('closing first-run setup only hides it; tray restores it and explicit exit ends the process', async () => {
  const h = harness({ argv: [] });
  await ready();
  const setup = h.windows[0];
  let prevented = false;
  setup.emit('close', {
    preventDefault: () => {
      prevented = true;
    },
  });
  assert.equal(prevented, true);
  assert.equal(setup.actions.at(-1), 'hide');
  h.app.tray.menu.find(item => item.label === 'Abrir Softphone').click();
  assert.equal(h.windows.length, 1);
  assert.deepEqual(setup.actions.slice(-2), ['show', 'focus']);
  h.app.tray.menu.find(item => item.label === 'Sair do JRC Softphone').click();
  assert.equal(h.app.exits, 1);
  assert.equal(h.pendingTimers.size, 0);
});
