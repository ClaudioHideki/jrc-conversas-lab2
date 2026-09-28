/* eslint max-classes-per-file: off, class-methods-use-this: off, no-restricted-syntax: off, no-loop-func: off, no-await-in-loop: off, no-script-url: off */
// Native API fakes and sequential event/timer scenarios are intentionally colocated.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { harness } = require('./electronHarness.cjs');
const policy = require('../src/policy.cjs');

test('second process exits before readiness/window creation', () => {
  const h = harness({ lock: false });
  assert.equal(h.app.quits, 1);
  assert.equal(h.app.readyCalls, 0);
  assert.equal(h.windows.length, 0);
});

test('preload exposes only fixed channels and no Node APIs', async () => {
  let bridge;
  const sent = [];
  vm.runInNewContext(
    readFileSync(path.join(__dirname, '../src/preload.cjs'), 'utf8'),
    {
      require: moduleName => {
        assert.equal(moduleName, 'electron');
        return {
          contextBridge: {
            exposeInMainWorld: (name, api) => {
              assert.equal(name, 'jrcSoftphoneDesktop');
              bridge = api;
            },
          },
          ipcRenderer: {
            send: (...args) => sent.push(args),
            invoke: async (...args) => {
              sent.push(args);
              return true;
            },
            on: () => {},
            removeListener: () => {},
          },
        };
      },
    }
  );
  assert.deepEqual(Object.keys(bridge).sort(), [
    'clearIncomingCall',
    'incomingCall',
    'onFloatingCommand',
    'onFloatingState',
    'openContact',
    'requestFloatingState',
    'sendFloatingCommand',
    'sendFloatingShutdownComplete',
    'sendFloatingState',
  ]);
  bridge.incomingCall({ callId: 'a', remote: '123' });
  bridge.clearIncomingCall({ callId: 'a' });
  assert.equal(
    await bridge.openContact({ accountId: '1', contactId: '2' }),
    true
  );
  assert.deepEqual(
    sent.map(args => args[0]),
    [
      'softphone:incoming-call',
      'softphone:clear-call',
      'softphone:open-contact',
    ]
  );
});

test('close/minimize preserve one renderer; second instance restores it; explicit quit closes', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const win = h.windows[0];
  let prevented = 0;
  for (const event of ['close', 'minimize'])
    win.emit(event, {
      preventDefault: () => {
        prevented += 1;
      },
    });
  assert.equal(prevented, 2);
  assert.deepEqual(win.actions, ['hide', 'hide']);
  win.minimized = true;
  h.app.emit('second-instance');
  assert.deepEqual(win.actions.slice(-3), ['restore', 'show', 'focus']);
  assert.equal(h.windows.length, 1);
  assert.equal(win.loads, 1);
  assert.doesNotThrow(() => h.app.emit('window-all-closed'));
  h.app.tray.menu.find(item => item.label === 'Sair do JRC Softphone').click();
  win.emit('close', {
    preventDefault: () => {
      prevented += 1;
    },
  });
  assert.equal(prevented, 2);
  assert.equal(h.app.tray.destroyed, true);
});

test('production window isolation, background, identity and nonsecret startup configuration', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const win = h.windows[0];
  const prefs = win.options.webPreferences;
  assert.equal(prefs.contextIsolation, true);
  assert.equal(prefs.nodeIntegration, false);
  assert.equal(prefs.sandbox, true);
  assert.equal(prefs.webSecurity, true);
  assert.equal(prefs.devTools, false);
  assert.equal(prefs.partition, 'jrc-softphone');
  assert.equal(prefs.backgroundThrottling, false);
  assert.equal(h.app.appId, 'br.com.jrcpabx.softphone');
  assert.equal(win.loadedUrl, 'https://jrc.example');
  assert.deepEqual(h.saved, [{ origin: 'https://jrc.example' }]);
  h.app.tray.menu
    .find(item => item.type === 'checkbox')
    .click({ checked: true });
  assert.deepEqual(h.app.loginSettings.args, []);
});

test('server URL permits only HTTPS or explicitly local unpackaged development', () => {
  assert.equal(
    policy.trustedUrl('blob:https://jrc.example/id', 'https://jrc.example'),
    false
  );
  assert.equal(
    policy.trustedUrl('https://jrc.example:444/app', 'https://jrc.example'),
    false
  );
  const input = { env: {}, isPackaged: true };
  for (const url of [
    'http://jrc.example',
    'file:///a',
    'javascript:alert(1)',
    'https://user:pass@jrc.example',
    'invalid',
  ]) {
    assert.throws(() =>
      policy.serverConfig({ ...input, argv: [`--server-url=${url}`] })
    );
  }
  assert.throws(() =>
    policy.serverConfig({
      ...input,
      argv: ['--development', '--server-url=http://localhost:3000'],
    })
  );
  assert.throws(() =>
    policy.serverConfig({
      ...input,
      isPackaged: false,
      argv: ['--server-url=http://localhost:3000'],
    })
  );
  const cfg = policy.serverConfig({
    ...input,
    isPackaged: false,
    argv: ['--development', '--server-url=http://localhost:3000/app?x=a=b'],
  });
  assert.equal(cfg.url, 'http://localhost:3000/app?x=a=b');
  assert.equal(
    policy.serverConfig({
      ...input,
      argv: [],
      savedOrigin: 'https://jrc.example',
    }).origin,
    'https://jrc.example'
  );
});

test('navigation/redirect and arbitrary windows cannot load privileged remote pages', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const win = h.windows[0];
  let blocked = 0;
  for (const event of ['will-navigate', 'will-redirect']) {
    win.webContents.emit(
      event,
      {
        preventDefault: () => {
          blocked += 1;
        },
      },
      'https://jrc.example.evil.test/'
    );
    win.webContents.emit(
      event,
      {
        preventDefault: () => {
          blocked += 1;
        },
      },
      'https://jrc.example/app/login'
    );
  }
  win.webContents.emit('will-frame-navigate', {
    url: 'https://jrc.example/app',
    isMainFrame: false,
    preventDefault: () => {
      blocked += 1;
    },
  });
  assert.equal(blocked, 3);
  win.webContents.emit('will-navigate', {
    url: 'blob:https://jrc.example/id',
    preventDefault: () => {
      blocked += 1;
    },
  });
  assert.equal(blocked, 4);
  assert.deepEqual(win.openHandler({ url: 'https://evil.test' }), {
    action: 'deny',
  });
  assert.equal(h.opened.length, 0);
  assert.deepEqual(
    win.openHandler({ url: 'https://jrc.example/app/accounts/1/contacts/2' }),
    { action: 'deny' }
  );
  assert.deepEqual(h.opened, ['https://jrc.example/app/accounts/1/contacts/2']);
  assert.equal(
    policy.externalUrl(
      'https://jrc.example/app?token=secret',
      'https://jrc.example'
    ),
    null
  );
});

test('audio permission requires authorized main frame, audio only, and both handlers', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const win = h.windows[0];
  const wc = win.webContents;
  const details = {
    requestingUrl: wc.getURL(),
    isMainFrame: true,
    mediaTypes: ['audio'],
  };
  let permitted;
  win.requestPermission(
    wc,
    'media',
    value => {
      permitted = value;
    },
    details
  );
  assert.equal(permitted, true);
  for (const change of [
    { mediaTypes: ['audio', 'video'] },
    { requestingUrl: 'https://evil.test' },
    { isMainFrame: false },
    { mediaTypes: [] },
  ]) {
    win.requestPermission(
      wc,
      'media',
      value => {
        permitted = value;
      },
      { ...details, ...change }
    );
    assert.equal(permitted, false);
  }
  win.requestPermission(
    wc,
    'notifications',
    value => {
      permitted = value;
    },
    details
  );
  assert.equal(permitted, false);
  const check = {
    requestingUrl: wc.getURL(),
    isMainFrame: true,
    mediaType: 'audio',
  };
  assert.equal(
    win.checkPermission(wc, 'media', 'https://jrc.example', check),
    true
  );
  assert.equal(
    win.checkPermission(wc, 'media', 'https://evil.test', check),
    false
  );
  assert.equal(
    win.checkPermission(wc, 'media', 'https://jrc.example', {
      ...check,
      mediaType: 'video',
    }),
    false
  );
});

test('IPC rejects absent/malformed/oversized payload and untrusted sender/frame', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const wc = h.windows[0].webContents;
  const event = { sender: wc, senderFrame: wc.mainFrame };
  for (const payload of [
    undefined,
    null,
    {},
    [],
    { callId: 'id', remote: '123', title: 'arbitrary' },
    { callId: 'x'.repeat(257), remote: '123' },
    { callId: 'id', remote: '\nspoof' },
  ]) {
    assert.doesNotThrow(() =>
      h.ipcMain.emit('softphone:incoming-call', event, payload)
    );
  }
  const payload = { callId: 'id', remote: '123' };
  h.ipcMain.emit('softphone:incoming-call', { ...event, sender: {} }, payload);
  h.ipcMain.emit(
    'softphone:incoming-call',
    { ...event, senderFrame: { url: wc.getURL() } },
    payload
  );
  wc.mainFrame.url = 'https://evil.test';
  h.ipcMain.emit('softphone:incoming-call', event, payload);
  assert.equal(h.notices.length, 0);
});

test('one native notification per call, click focuses, matching end closes it', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const win = h.windows[0];
  const wc = win.webContents;
  const event = { sender: wc, senderFrame: wc.mainFrame };
  const payload = { callId: 'id', remote: '123' };
  h.ipcMain.emit('softphone:incoming-call', event, payload);
  h.ipcMain.emit('softphone:incoming-call', event, payload);
  assert.equal(h.notices.length, 1);
  assert.equal(h.notices[0].options.title, 'JRC Softphone');
  h.notices[0].emit('click');
  const floating = h.windows[1];
  assert.match(floating.loadedFile, /floating[\\/]index\.html$/);
  assert.deepEqual(floating.actions.slice(-2), ['show', 'focus']);
  h.ipcMain.emit('softphone:clear-call', event, { callId: 'other' });
  assert.equal(h.notices[0].closed, undefined);
  h.ipcMain.emit('softphone:clear-call', event, { callId: 'id' });
  assert.equal(h.notices[0].closed, true);
  assert.equal(win.flash, false);
  h.ipcMain.emit('softphone:incoming-call', event, payload);
  assert.equal(h.notices.length, 1);
});

test('floating control is local, relays commands to the one JRC renderer and never creates SIP', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const main = h.windows[0];
  const event = {
    sender: main.webContents,
    senderFrame: main.webContents.mainFrame,
  };
  const state = {
    registered: true,
    status: 'Chamada recebida',
    extension: '101',
    destination: '',
    remote: '11999999999',
    duration: '00:00',
    incoming: true,
    sessionActive: true,
    established: false,
    muted: false,
    held: false,
    holdPending: false,
    transferring: false,
    errorMessage: '',
  };
  h.ipcMain.emit('softphone:floating-state', event, state);
  assert.equal(h.windows.length, 2);
  const floating = h.windows[1];
  assert.match(floating.loadedFile, /floating[\\/]index\.html$/);
  assert.equal(floating.options.webPreferences.nodeIntegration, false);
  assert.equal(floating.options.webPreferences.contextIsolation, true);
  floating.emit('ready-to-show');
  assert.deepEqual(floating.actions.slice(-2), ['show', 'focus']);
  assert.equal(floating.webContents.sent.at(-1)[0], 'softphone:floating-state');
  assert.equal(floating.webContents.sent.at(-1)[1].extension, '101');
  h.ipcMain.emit(
    'softphone:floating-command',
    {
      sender: floating.webContents,
      senderFrame: floating.webContents.mainFrame,
    },
    { action: 'answer' }
  );
  assert.deepEqual(main.webContents.sent.at(-1), [
    'softphone:floating-command',
    { action: 'answer' },
  ]);
  h.ipcMain.emit(
    'softphone:floating-command',
    { sender: main.webContents },
    { action: 'hangup' }
  );
  assert.equal(main.webContents.sent.length, 1);
  let prevented = false;
  floating.emit('close', {
    preventDefault: () => {
      prevented = true;
    },
  });
  assert.equal(prevented, true);
  assert.equal(floating.actions.at(-1), 'hide');
  assert.equal(
    readFileSync(path.join(__dirname, '../floating/app.js'), 'utf8').match(
      /sip\.js|UserAgent/g
    ),
    null
  );
});

test('first successful SIP registration opens idle softphone before any call and tray reopens it', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const main = h.windows[0];
  const state = {
    registered: true,
    status: 'Registrado',
    extension: '101',
    destination: '',
    remote: '—',
    duration: '00:00',
    incoming: false,
    sessionActive: false,
    established: false,
    muted: false,
    held: false,
    holdPending: false,
    transferring: false,
    errorMessage: '',
  };
  h.ipcMain.emit(
    'softphone:floating-state',
    { sender: main.webContents, senderFrame: main.webContents.mainFrame },
    state
  );
  assert.equal(h.windows.length, 2);
  h.windows[1].emit('ready-to-show');
  assert.deepEqual(h.windows[1].actions.slice(-2), ['show', 'focus']);
  h.windows[1].emit('close', { preventDefault() {} });
  assert.equal(h.windows[1].actions.at(-1), 'hide');
  const menuItem = h.app.tray.menu.find(
    item => item.label === 'Abrir Softphone'
  );
  assert.ok(menuItem);
  menuItem.click(menuItem, main, {});
  const floating = h.windows[1];
  floating.emit('ready-to-show');
  assert.deepEqual(floating.webContents.sent.at(-1), [
    'softphone:floating-state',
    state,
  ]);
  assert.equal((main.webContents.sent || []).length, 0);
});

test('notification rate limit bounds repeated distinct IDs', () => {
  let now = 0;
  const accept = policy.notificationGate(() => now);
  for (let id = 0; id < 5; id += 1) assert.equal(accept(String(id)), true);
  assert.equal(accept('sixth'), false);
  now = 10000;
  assert.equal(accept('sixth'), true);
  assert.equal(accept('0'), false);
});

test('external contact IPC cannot carry URLs, tokens or path injection', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const wc = h.windows[0].webContents;
  const event = { sender: wc, senderFrame: wc.mainFrame };
  const handler = h.ipcMain['softphone:open-contact'];
  assert.equal(
    await handler(event, { accountId: '1', contactId: '../2' }),
    false
  );
  assert.equal(
    await handler(event, { accountId: '1', contactId: '2', token: 'secret' }),
    false
  );
  assert.equal(
    await handler({ ...event, sender: {} }, { accountId: '1', contactId: '2' }),
    false
  );
  assert.equal(await handler(event, { accountId: '1', contactId: '2' }), true);
  assert.deepEqual(h.opened, ['https://jrc.example/app/accounts/1/contacts/2']);
});

test('invalid tray resource aborts before creating a hidden SIP window', async () => {
  const h = harness({ emptyIcon: true });
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  assert.equal(h.windows.length, 0);
  assert.equal(h.app.quits, 1);
  assert.equal(h.errors.length, 1);
});

test('failed initial load has bounded backoff and quit cancels recovery', async () => {
  const h = harness({ failLoad: true });
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const delays = [];
  while (h.pendingTimers.size) {
    const [id, timer] = h.pendingTimers.entries().next().value;
    delays.push(timer.delay);
    h.pendingTimers.delete(id);
    timer.callback();
    await new Promise(resolve => {
      setImmediate(resolve);
    });
    assert.ok(delays.length <= 5);
  }
  assert.deepEqual(delays, [1000, 5000, 15000, 30000, 60000]);
  assert.equal(h.windows[0].loads, 6);
  assert.equal(
    h.app.tray.menu.find(item => item.label === 'Tentar carregar novamente')
      .enabled,
    true
  );
  h.app.tray.menu
    .find(item => item.label === 'Tentar carregar novamente')
    .click();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  h.app.quit();
  assert.equal(h.pendingTimers.size, 1);
  assert.equal([...h.pendingTimers.values()][0].delay, 3000);
});

test('renderer crash schedules one reload, repeated crashes do not reset the budget', async () => {
  const h = harness();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  const wc = h.windows[0].webContents;
  wc.emit('render-process-gone');
  wc.emit('render-process-gone');
  assert.equal(h.pendingTimers.size, 1);
  const [id, timer] = h.pendingTimers.entries().next().value;
  assert.equal(timer.delay, 1000);
  h.pendingTimers.delete(id);
  timer.callback();
  await new Promise(resolve => {
    setImmediate(resolve);
  });
  wc.emit('did-finish-load');
  wc.emit('render-process-gone');
  assert.equal([...h.pendingTimers.values()][0].delay, 5000);
});
