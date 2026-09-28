/* eslint max-classes-per-file: off, class-methods-use-this: off */
// Real UI, preload, main-process policy, composable, SipClient and SipRegisterer.
// Only native Electron APIs and the SIP.js network/media boundary are simulated.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import { JSDOM } from 'jsdom';
import { effectScope, nextTick } from 'vue';
import { flushPromises } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const sip = vi.hoisted(() => ({ agents: [], registerers: [], calls: [] }));
vi.mock('dashboard/api/sipCredentials', () => ({
  default: {
    getMine: vi.fn(async () => ({
      data: {
        configured: true,
        enabled: true,
        extension: '101',
        username: 'test-user',
        password: 'test-password-not-for-ipc',
        sip_domain: 'pbx.example',
        websocket_url: 'wss://pbx.example',
      },
    })),
  },
}));
vi.mock('sip.js', () => {
  class StateEmitter {
    listeners = [];

    addListener(fn) {
      this.listeners.push(fn);
    }

    emit(state) {
      this.listeners.forEach(fn => fn(state));
    }
  }
  class Session {
    state = 'Initial';

    stateChange = new StateEmitter();

    id = `call-${sip.calls.length}`;

    remoteIdentity = { uri: { user: '1410' } };

    microphone = { kind: 'audio', enabled: true, stop: vi.fn() };

    speaker = { kind: 'audio', enabled: true, stop: vi.fn() };

    sessionDescriptionHandler = {
      sendDtmf: vi.fn().mockReturnValue(true),
      peerConnection: {
        addEventListener: vi.fn(),
        getSenders: () => [{ track: this.microphone }],
        getReceivers: () => [{ track: this.speaker }],
      },
    };

    transition(state) {
      this.state = state;
      this.stateChange.emit(state);
    }

    accept = vi.fn(async () => this.transition('Established'));

    reject = vi.fn(async () => this.transition('Terminated'));

    bye = vi.fn(async () => this.transition('Terminated'));

    cancel = vi.fn(async () => this.transition('Terminated'));

    progress = vi.fn();

    invite = vi.fn(async options => {
      if (this.state === 'Established') options.requestDelegate.onAccept();
      else this.transition('Establishing');
    });

    constructor() {
      sip.calls.push(this);
    }
  }
  class Invitation extends Session {}
  class Inviter extends Session {
    constructor(agent, target) {
      super();
      this.agent = agent;
      this.target = target;
    }
  }
  class UserAgent {
    static makeURI(value) {
      return value;
    }

    constructor(options) {
      this.options = options;
      sip.agents.push(this);
    }

    start = vi.fn(async () => this.options.delegate.onConnect());

    stop = vi.fn(async () => {});
  }
  class Registerer {
    stateChange = new StateEmitter();

    state = 'Initial';

    registerCalls = vi.fn();

    async register(options) {
      this.registerCalls(options);
      this.state = 'Registered';
      this.stateChange.emit(this.state);
      options.requestDelegate.onAccept();
    }

    unregister = vi.fn(async () => {
      this.state = 'Unregistered';
    });

    constructor() {
      sip.registerers.push(this);
    }
  }
  return {
    Invitation,
    Inviter,
    UserAgent,
    Registerer,
    SessionState: {
      Initial: 'Initial',
      Establishing: 'Establishing',
      Established: 'Established',
      Terminating: 'Terminating',
      Terminated: 'Terminated',
    },
    RegistererState: {
      Registered: 'Registered',
      Unregistered: 'Unregistered',
      Terminated: 'Terminated',
    },
  };
});

const require = createRequire(import.meta.url);
const { harness } = require('./electronHarness.cjs');
const readDesktop = file => readFileSync(path.resolve('desktop', file), 'utf8');

// Simulate structured-cloned IPC at both renderer boundaries; run the actual preload.
function connectRenderer(h, win, target, preload = 'src/preload.cjs') {
  const ipcRenderer = new EventEmitter();
  ipcRenderer.send = (channel, payload) =>
    h.ipcMain.emit(
      channel,
      {
        sender: win.webContents,
        senderFrame: win.webContents.mainFrame,
      },
      payload === undefined ? undefined : JSON.parse(JSON.stringify(payload))
    );
  const originalSend = win.webContents.send;
  ipcRenderer.invoke = async (channel, payload) =>
    h.ipcMain[channel](
      {
        sender: win.webContents,
        senderFrame: win.webContents.mainFrame,
      },
      payload === undefined ? undefined : JSON.parse(JSON.stringify(payload))
    );
  win.webContents.send = (channel, payload) => {
    originalSend(channel, payload);
    ipcRenderer.emit(channel, {}, JSON.parse(JSON.stringify(payload)));
  };
  vm.runInNewContext(readDesktop(preload), {
    require: () => ({
      ipcRenderer,
      contextBridge: {
        exposeInMainWorld: (name, api) => {
          target[name] = api;
        },
      },
    }),
  });
  return ipcRenderer;
}

describe('floating Desktop ↔ existing Web SIP session', () => {
  let h;
  let api;
  let useSipWebphone;
  let ui;
  let renderer;
  let owner;
  let settingsUi;
  const element = id => ui.window.document.getElementById(id);
  const click = async id => {
    element(id).click();
    await flushPromises();
  };
  const receive = async () => {
    const { Invitation } = await import('sip.js');
    const session = new Invitation();
    sip.agents[0].options.delegate.onInvite(session);
    await flushPromises();
    return session;
  };

  beforeEach(async () => {
    vi.resetModules();
    sip.agents.length = 0;
    sip.registerers.length = 0;
    sip.calls.length = 0;
    localStorage.clear();
    vi.spyOn(console, 'info').mockImplementation(() => {});
    vi.stubGlobal(
      'MediaStream',
      class {
        getTracks() {
          return [];
        }
      }
    );
    h = harness();
    await flushPromises();
    renderer = connectRenderer(h, h.windows[0], window);
    ({ useSipWebphone } = await import(
      '../../app/javascript/dashboard/routes/dashboard/webphone/useSipWebphone'
    ));
    owner = effectScope();
    api = owner.run(() => useSipWebphone());
    expect(h.windows).toHaveLength(1);
    await api.initialize(1);
    await nextTick();
    expect(h.windows).toHaveLength(2);
    ui = new JSDOM(readDesktop('floating/index.html'), {
      runScripts: 'outside-only',
    });
    connectRenderer(h, h.windows[1], ui.window);
    ui.window.eval(readDesktop('floating/app.js'));
    h.windows[1].emit('ready-to-show');
  });

  afterEach(async () => {
    await api?.shutdown();
    owner?.stop();
    ui?.window.close();
    settingsUi?.window.close();
    settingsUi = undefined;
    delete window.jrcSoftphoneDesktop;
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('first successful REGISTER opens idle window before any call; tray and main hide retain the same agent', async () => {
    expect(sip.calls).toHaveLength(0);
    expect(h.windows[1].actions.slice(-2)).toEqual(['show', 'focus']);
    expect(element('extension').textContent).toBe('Ramal: 101');
    expect(element('status').textContent).toBe('Disponível / Registrado');
    expect(element('dial-panel').classList.contains('hidden')).toBe(false);
    expect(ui.window.document.querySelectorAll('[data-tone]')).toHaveLength(12);
    h.windows[1].emit('close', { preventDefault: vi.fn() });
    expect(h.windows[1].actions.at(-1)).toBe('hide');
    api.destination.value = '404';
    await nextTick();
    expect(h.windows[1].actions.at(-1)).toBe('hide');
    h.windows[0].emit('close', { preventDefault: vi.fn() });
    h.windows[0].emit('minimize', { preventDefault: vi.fn() });
    const item = h.app.tray.menu.find(
      entry => entry.label === 'Abrir Softphone'
    );
    item.click(item, h.windows[0], {});
    expect(h.windows[1].actions.slice(-2)).toEqual(['show', 'focus']);
    expect(element('extension').textContent).toBe('Ramal: 101');
    await useSipWebphone().initialize(1);
    expect(sip.agents).toHaveLength(1);
    expect(sip.registerers).toHaveLength(1);
    expect(sip.registerers[0].registerCalls).toHaveBeenCalledOnce();
    expect(sip.registerers[0].unregister).not.toHaveBeenCalled();
    await click('open-main');
    expect(h.windows[0].actions.slice(-2)).toEqual(['show', 'focus']);
    expect(h.windows[0].loads).toBe(1);
  });

  it('dial field and keypad share destination, originate on existing agent, and return to idle on hangup', async () => {
    element('destination').value = '20';
    element('destination').focus();
    element('destination').dispatchEvent(new ui.window.Event('input'));
    await flushPromises();
    ui.window.document.querySelector('[data-tone="2"]').click();
    await flushPromises();
    expect(api.destination.value).toBe('202');
    expect(element('destination').value).toBe('202');
    await click('dial');
    const session = sip.calls[0];
    expect(session.target).toBe('sip:202@pbx.example');
    expect(session.agent).toBe(sip.agents[0]);
    expect(api.sessionActive.value).toBe(true);
    session.transition('Established');
    await nextTick();
    expect(element('call-actions').classList.contains('hidden')).toBe(false);
    await click('hangup');
    expect(session.bye).toHaveBeenCalledOnce();
    expect(api.sessionActive.value).toBe(false);
    expect(element('dial-panel').classList.contains('hidden')).toBe(false);
    expect(element('status').textContent).toBe('Disponível / Registrado');
    expect(sip.agents).toHaveLength(1);
  });

  it('hidden incoming opens with identity; answer, duration, mute/unmute, hold/resume, DTMF and hangup round-trip', async () => {
    h.windows[1].emit('close', { preventDefault: vi.fn() });
    const session = await receive();
    expect(element('remote').textContent).toBe('1410');
    expect(element('incoming-actions').classList.contains('hidden')).toBe(
      false
    );
    expect(h.windows[1].actions.slice(-2)).toEqual(['show', 'focus']);
    h.notices[0].emit('click', { nativeEvent: true });
    expect(element('extension').textContent).toBe('Ramal: 101');
    vi.useFakeTimers({
      toFake: [
        'Date',
        'setTimeout',
        'clearTimeout',
        'setInterval',
        'clearInterval',
      ],
    });
    await click('answer');
    expect(session.accept).toHaveBeenCalledOnce();
    expect(api.established.value).toBe(true);
    expect(element('incoming-actions').classList.contains('hidden')).toBe(true);
    expect(h.notices[0].closed).toBe(true);
    await vi.advanceTimersByTimeAsync(2000);
    expect(element('duration').textContent).toBe('00:02');
    await click('mute');
    expect(api.muted.value).toBe(true);
    expect(session.microphone.enabled).toBe(false);
    expect(element('mute').textContent).toBe('Ativar microfone');
    await click('mute');
    expect(api.muted.value).toBe(false);
    expect(session.microphone.enabled).toBe(true);
    await click('hold');
    expect(
      session.invite.mock.calls[0][0].sessionDescriptionHandlerOptions
    ).toEqual({ hold: true });
    expect(api.held.value).toBe(true);
    expect(element('hold').textContent).toBe('Retomar');
    await click('hold');
    expect(api.held.value).toBe(false);
    expect(session.microphone.enabled).toBe(true);
    ui.window.document
      .querySelectorAll('[data-tone]')
      .forEach(button => button.click());
    await flushPromises();
    expect(
      session.sessionDescriptionHandler.sendDtmf.mock.calls
        .map(args => args[0])
        .join('')
    ).toBe('123456789*0#');
    await click('hangup');
    expect(session.bye).toHaveBeenCalledOnce();
    expect(element('duration').textContent).toBe('00:00');
    expect(element('dial-panel').classList.contains('hidden')).toBe(false);
    expect(sip.registerers[0].unregister).not.toHaveBeenCalled();
  });

  it('reject acts on the incoming invitation without unregister; next call can arrive', async () => {
    const session = await receive();
    await click('reject');
    expect(session.reject).toHaveBeenCalledWith({
      statusCode: 486,
      reasonPhrase: 'Busy Here',
    });
    expect(api.incoming.value).toBe(false);
    expect(element('status').textContent).toBe('Disponível / Registrado');
    await receive();
    expect(api.incoming.value).toBe(true);
    expect(sip.agents).toHaveLength(1);
    expect(sip.registerers[0].registerCalls).toHaveBeenCalledOnce();
  });

  it.each([
    ['immediate', '*3202#'],
    ['supervised', '*4202#'],
  ])(
    'transfer %s uses the existing PABX DTMF sequence %s',
    async (mode, tones) => {
      const session = await receive();
      await click('answer');
      vi.useFakeTimers({
        toFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval'],
      });
      element('transfer-destination').value = '202';
      ui.window.document.querySelector(`[data-transfer="${mode}"]`).click();
      await nextTick();
      expect(api.transferring.value).toBe(true);
      await vi.advanceTimersByTimeAsync(5000);
      expect(
        session.sessionDescriptionHandler.sendDtmf.mock.calls
          .map(args => args[0])
          .join('')
      ).toBe(tones);
      expect(api.transferring.value).toBe(false);
      expect(sip.calls).toHaveLength(1);
    }
  );

  it('view disposal does not stop state sync, repeated consumers do not duplicate listeners and ready requests recover state', async () => {
    owner.stop();
    const web = useSipWebphone();
    expect(web.destination).toBe(api.destination);
    expect(renderer.listenerCount('softphone:floating-command')).toBe(1);
    web.destination.value = '303';
    await nextTick();
    expect(element('destination').value).toBe('303');
    element('extension').textContent = '';
    ui.window.jrcSoftphoneDesktop.requestFloatingState();
    expect(element('extension').textContent).toBe('Ramal: 101');
    const session = await receive();
    await web.answer();
    await nextTick();
    expect(element('call-state').textContent).toBe('Em chamada');
    expect(session.accept).toHaveBeenCalledOnce();
    await web.setMuted(true);
    await nextTick();
    expect(element('mute').textContent).toBe('Ativar microfone');
    expect(sip.agents).toHaveLength(1);
    const snapshots = h.windows[1].webContents.sent.filter(
      ([name]) => name === 'softphone:floating-state'
    );
    expect(JSON.stringify(snapshots)).not.toContain(
      'test-password-not-for-ipc'
    );
    expect(JSON.stringify(snapshots)).not.toContain('test-user');
  });

  it('explicit tray exit unregisters, cleans up listeners and terminates Desktop', async () => {
    h.app.tray.menu
      .find(item => item.label === 'Sair do JRC Softphone')
      .click();
    await flushPromises();
    expect(sip.registerers[0].unregister).toHaveBeenCalledOnce();
    expect(sip.agents[0].stop).toHaveBeenCalledOnce();
    expect(renderer.listenerCount('softphone:floating-command')).toBe(0);
    expect(h.app.exits).toBe(1);
    expect(h.app.tray.destroyed).toBe(true);
  });

  it('logout removes the bridge and the next login opens the idle window with one new registration', async () => {
    await api.shutdown();
    expect(sip.registerers[0].unregister).toHaveBeenCalledOnce();
    expect(element('extension').textContent).toBe('Ramal: —');
    expect(renderer.listenerCount('softphone:floating-command')).toBe(0);
    h.windows[1].emit('close', { preventDefault: vi.fn() });
    await api.initialize(1);
    await nextTick();
    expect(h.windows).toHaveLength(2);
    expect(h.windows[1].actions.slice(-2)).toEqual(['show', 'focus']);
    expect(element('extension').textContent).toBe('Ramal: 101');
    expect(sip.calls).toHaveLength(0);
    expect(renderer.listenerCount('softphone:floating-command')).toBe(1);
    // Sequential sessions after logout, never concurrent registrations.
    expect(sip.registerers.map(item => item.state)).toEqual([
      'Unregistered',
      'Registered',
    ]);
    expect(sip.registerers[1].registerCalls).toHaveBeenCalledOnce();
  });

  it('rejects foreign-frame commands and malformed dial data before reaching the SIP session', async () => {
    const wc = h.windows[1].webContents;
    h.ipcMain.emit(
      'softphone:floating-command',
      {
        sender: wc,
        senderFrame: { url: wc.mainFrame.url },
      },
      { action: 'dial', number: '202' }
    );
    h.ipcMain.emit(
      'softphone:floating-command',
      {
        sender: wc,
        senderFrame: wc.mainFrame,
      },
      { action: 'dial', number: '202', password: 'not-allowed' }
    );
    ui.window.jrcSoftphoneDesktop.sendFloatingCommand({
      action: 'setDestination',
      number: 'https://not-a-number.example',
    });
    await flushPromises();
    expect(sip.calls).toHaveLength(0);
    expect(api.destination.value).toBe('');
  });

  it('first-run form → HTTPS origin → login/REGISTER → floating opens before any call', async () => {
    await api.shutdown();
    owner.stop();
    ui.window.close();
    sip.agents.length = 0;
    sip.registerers.length = 0;
    h = harness({ argv: [] });
    await flushPromises();
    expect(h.windows).toHaveLength(1);
    expect(sip.agents).toHaveLength(0);
    settingsUi = new JSDOM(readDesktop('setup/index.html'), {
      runScripts: 'outside-only',
    });
    connectRenderer(
      h,
      h.windows[0],
      settingsUi.window,
      'src/setup-preload.cjs'
    );
    settingsUi.window.eval(readDesktop('setup/app.js'));
    await flushPromises();
    const document = settingsUi.window.document;
    expect(document.getElementById('server-url').value).toBe('');
    document.getElementById('server-url').value =
      'https://client.example/app/login?discard=true';
    document
      .getElementById('server-form')
      .dispatchEvent(
        new settingsUi.window.Event('submit', { cancelable: true })
      );
    await flushPromises();
    expect(h.windows[1].loadedUrl).toBe('https://client.example');
    expect(document.getElementById('server-url').value).toBe(
      'https://client.example'
    );
    expect(
      document.getElementById('switch-warning').classList.contains('hidden')
    ).toBe(false);
    expect(sip.agents).toHaveLength(0);
    // A newly loaded remote renderer has its own module context, just like Electron.
    vi.resetModules();
    connectRenderer(h, h.windows[1], window);
    ({ useSipWebphone } = await import(
      '../../app/javascript/dashboard/routes/dashboard/webphone/useSipWebphone'
    ));
    api = useSipWebphone();
    await api.initialize(1);
    await nextTick();
    expect(h.windows).toHaveLength(3);
    ui = new JSDOM(readDesktop('floating/index.html'), {
      runScripts: 'outside-only',
    });
    connectRenderer(h, h.windows[2], ui.window);
    ui.window.eval(readDesktop('floating/app.js'));
    h.windows[2].emit('ready-to-show');
    expect(element('extension').textContent).toBe('Ramal: 101');
    expect(element('status').textContent).toBe('Disponível / Registrado');
    expect(sip.calls).toHaveLength(0);
    expect(sip.agents).toHaveLength(1);
    expect(sip.registerers).toHaveLength(1);
    expect(sip.registerers[0].registerCalls).toHaveBeenCalledOnce();
  });

  it('switching via local settings ends real shared call/session before a new environment can register', async () => {
    const session = await receive();
    await click('answer');
    h.app.tray.menu
      .find(item => item.label === 'Configurações / Alterar servidor JRC')
      .click();
    settingsUi = new JSDOM(readDesktop('setup/index.html'), {
      runScripts: 'outside-only',
    });
    connectRenderer(
      h,
      h.windows[2],
      settingsUi.window,
      'src/setup-preload.cjs'
    );
    settingsUi.window.eval(readDesktop('setup/app.js'));
    await flushPromises();
    const document = settingsUi.window.document;
    expect(document.getElementById('server-url').value).toBe(
      'https://jrc.example'
    );
    expect(
      document.getElementById('switch-warning').classList.contains('hidden')
    ).toBe(false);
    document.getElementById('server-url').value =
      'https://another-client.example';
    document
      .getElementById('server-form')
      .dispatchEvent(
        new settingsUi.window.Event('submit', { cancelable: true })
      );
    await flushPromises();
    expect(session.bye).toHaveBeenCalledOnce();
    expect(session.microphone.stop).toHaveBeenCalled();
    expect(sip.registerers[0].unregister).toHaveBeenCalledOnce();
    expect(sip.agents[0].stop).toHaveBeenCalledOnce();
    expect(h.windows[0].isDestroyed()).toBe(true);
    expect(h.windows[1].isDestroyed()).toBe(true);
    expect(renderer.listenerCount('softphone:floating-command')).toBe(0);
    expect(h.windows[3].loadedUrl).toBe('https://another-client.example');
    expect(h.app.exits).toBeUndefined();
    expect(
      sip.registerers.filter(item => item.state === 'Registered')
    ).toHaveLength(0);
    vi.resetModules();
    connectRenderer(h, h.windows[3], window);
    ({ useSipWebphone } = await import(
      '../../app/javascript/dashboard/routes/dashboard/webphone/useSipWebphone'
    ));
    api = useSipWebphone();
    await api.initialize(1);
    await nextTick();
    expect(sip.agents).toHaveLength(2);
    expect(sip.registerers.map(item => item.state)).toEqual([
      'Unregistered',
      'Registered',
    ]);
    expect(sip.registerers[1].registerCalls).toHaveBeenCalledOnce();
    expect(h.windows).toHaveLength(5);
    h.windows[4].emit('ready-to-show');
    expect(h.windows[4].actions.slice(-2)).toEqual(['show', 'focus']);
    expect(sip.calls).toHaveLength(1);
  });
});
