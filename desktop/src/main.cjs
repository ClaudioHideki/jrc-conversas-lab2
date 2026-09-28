const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { serverSettings } = require('./server-settings.cjs');
const {
  APP_ID,
  serverConfig,
  serverOrigin,
  trustedUrl,
  trustedSender,
  audioPermission,
  incomingPayload,
  clearPayload,
  floatingState,
  floatingCommand,
  contactUrl,
  externalUrl,
  notificationGate,
} = require('./policy.cjs');

function startDesktop(
  electron,
  {
    argv = process.argv,
    env = process.env,
    fileSystem = fs,
    timers = { setTimeout, clearTimeout },
  } = {}
) {
  const {
    app,
    BrowserWindow,
    Menu,
    nativeImage,
    Notification,
    Tray,
    ipcMain,
    shell,
    dialog,
  } = electron;
  let settings;
  try {
    settings = serverSettings(app, fileSystem);
  } catch {
    dialog.showErrorBox(
      'JRC Softphone',
      'Não foi possível acessar o diretório de configuração.'
    );
    app.quit();
    return;
  }
  if (!app.requestSingleInstanceLock()) {
    app.quit();
    return;
  }
  app.setAppUserModelId(APP_ID);
  let mainWindow;
  let floatingWindow;
  let latestFloatingState;
  let openedAfterRegistration = false;
  let tray;
  let config;
  let setupWindow;
  let setupError = '';
  let switchingServer = false;
  let pendingServerShutdown;
  let retiredSession;
  const setupFile = path.join(__dirname, '../setup/index.html');
  let quitting = false;
  let finalQuit = false;
  let shutdownTimer;
  let notification;
  let pendingCallId;
  let recoveryTimer;
  let stabilityTimer;
  let recoveryAttempt = 0;
  let unavailable = true;
  let loading = false;
  let lastExternalOpen = -Infinity;
  let permitNotification = notificationGate();
  const recoveryDelays = [1000, 5000, 15000, 30000, 60000];

  const clearNotification = () => {
    notification?.close();
    notification = undefined;
    pendingCallId = undefined;
    if (mainWindow && !mainWindow.isDestroyed()) mainWindow.flashFrame(false);
  };
  const showWindow = () => {
    if (!mainWindow || mainWindow.isDestroyed()) {
      // Function declarations are initialized before native callbacks run.
      // eslint-disable-next-line no-use-before-define
      showSetup();
      return;
    }
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
    mainWindow.flashFrame(false);
  };
  const sendFloatingState = () => {
    if (floatingWindow && !floatingWindow.isDestroyed() && latestFloatingState)
      floatingWindow.webContents.send(
        'softphone:floating-state',
        latestFloatingState
      );
  };
  // Native menu/notification callbacks receive event objects, never SIP state.
  const showFloatingWindow = () => {
    if (switchingServer || quitting) return;
    if (!config || !mainWindow || mainWindow.isDestroyed()) {
      // eslint-disable-next-line no-use-before-define
      showSetup();
      return;
    }
    if (!floatingWindow || floatingWindow.isDestroyed()) {
      floatingWindow = new BrowserWindow({
        width: 390,
        height: 650,
        minWidth: 350,
        minHeight: 560,
        show: false,
        title: 'JRC Softphone',
        autoHideMenuBar: true,
        webPreferences: {
          preload: path.join(__dirname, 'preload.cjs'),
          contextIsolation: true,
          nodeIntegration: false,
          sandbox: true,
          webSecurity: true,
          webviewTag: false,
          devTools: !app.isPackaged,
        },
      });
      floatingWindow.webContents.setWindowOpenHandler(() => ({
        action: 'deny',
      }));
      floatingWindow.webContents.on('will-navigate', event =>
        event.preventDefault()
      );
      floatingWindow.once('ready-to-show', () => {
        sendFloatingState();
        floatingWindow.show();
        floatingWindow.focus();
      });
      floatingWindow.on('close', event => {
        if (!quitting) {
          event.preventDefault();
          floatingWindow.hide();
        }
      });
      floatingWindow.on('closed', () => {
        floatingWindow = undefined;
      });
      floatingWindow
        .loadFile(path.join(__dirname, '../floating/index.html'))
        .catch(() => floatingWindow?.hide());
      return;
    }
    sendFloatingState();
    if (floatingWindow.isMinimized()) floatingWindow.restore();
    floatingWindow.show();
    floatingWindow.focus();
  };
  const loginSettings = () => ({
    path: process.execPath,
    args: [],
  });
  const refreshTray = () => {
    if (!tray) return;
    tray.setToolTip(
      unavailable ? 'JRC Softphone — conexão indisponível' : 'JRC Softphone'
    );
    tray.setContextMenu(
      Menu.buildFromTemplate([
        { label: 'Abrir JRC Softphone', click: showWindow },
        { label: 'Abrir Softphone', click: showFloatingWindow },
        {
          label: 'Configurações / Alterar servidor JRC',
          enabled: !switchingServer,
          // eslint-disable-next-line no-use-before-define
          click: () => showSetup(),
        },
        {
          label: 'Tentar carregar novamente',
          enabled:
            unavailable &&
            Boolean(config) &&
            Boolean(mainWindow) &&
            !switchingServer,
          click: () => {
            recoveryAttempt = 0;
            timers.clearTimeout(recoveryTimer);
            recoveryTimer = undefined;
            // eslint-disable-next-line no-use-before-define
            loadWindow();
          },
        },
        { type: 'separator' },
        {
          label: 'Iniciar com o Windows',
          type: 'checkbox',
          enabled: app.isPackaged,
          checked:
            app.isPackaged &&
            app.getLoginItemSettings(loginSettings()).openAtLogin,
          click: item =>
            app.setLoginItemSettings({
              ...loginSettings(),
              openAtLogin: item.checked,
            }),
        },
        { label: 'Sair do JRC Softphone', click: () => app.quit() },
      ])
    );
  };
  const scheduleRecovery = () => {
    if (quitting || switchingServer) return;
    clearNotification();
    unavailable = true;
    timers.clearTimeout(stabilityTimer);
    refreshTray();
    if (recoveryTimer || recoveryAttempt >= recoveryDelays.length) return;
    recoveryTimer = timers.setTimeout(() => {
      recoveryTimer = undefined;
      // eslint-disable-next-line no-use-before-define
      loadWindow();
    }, recoveryDelays[recoveryAttempt]);
    recoveryAttempt += 1;
  };
  async function loadWindow() {
    if (
      quitting ||
      switchingServer ||
      !config ||
      loading ||
      !mainWindow ||
      mainWindow.isDestroyed()
    )
      return;
    const windowToLoad = mainWindow;
    loading = true;
    try {
      await windowToLoad.loadURL(config.url);
    } catch {
      // Never log a remote URL, cookies, tokens or raw Electron errors.
      if (mainWindow === windowToLoad) scheduleRecovery();
    } finally {
      if (mainWindow === windowToLoad) loading = false;
    }
  }
  const openExternal = async url => {
    const allowed = externalUrl(url, config.origin);
    if (!allowed || Date.now() - lastExternalOpen < 1000) return false;
    lastExternalOpen = Date.now();
    try {
      await shell.openExternal(allowed);
      return true;
    } catch {
      dialog.showErrorBox(
        'JRC Softphone',
        'Não foi possível abrir o navegador padrão.'
      );
      return false;
    }
  };
  const configureWindow = () => {
    mainWindow = new BrowserWindow({
      width: 1180,
      height: 820,
      minWidth: 900,
      minHeight: 650,
      show: false,
      webPreferences: {
        preload: path.join(__dirname, 'preload.cjs'),
        // No persist: prefix: cookies, tokens and web storage live only for this process.
        partition: 'jrc-softphone',
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
        webSecurity: true,
        webviewTag: false,
        devTools: !app.isPackaged,
        backgroundThrottling: false,
        autoplayPolicy: 'no-user-gesture-required',
      },
    });
    const contents = mainWindow.webContents;
    contents.session.setPermissionCheckHandler(
      (webContents, permission, origin, details) =>
        audioPermission(
          webContents,
          mainWindow,
          config.origin,
          permission,
          details,
          origin
        )
    );
    contents.session.setPermissionRequestHandler(
      (webContents, permission, callback, details) =>
        callback(
          audioPermission(
            webContents,
            mainWindow,
            config.origin,
            permission,
            details
          )
        )
    );
    contents.setWindowOpenHandler(({ url }) => {
      if (trustedUrl(contents.getURL(), config.origin)) openExternal(url);
      return { action: 'deny' };
    });
    contents.on('will-navigate', (event, url) => {
      if (!trustedUrl(event.url || url, config.origin)) event.preventDefault();
    });
    contents.on('will-frame-navigate', event => {
      if (!event.isMainFrame || !trustedUrl(event.url, config.origin))
        event.preventDefault();
    });
    contents.on('will-redirect', (event, url) => {
      if (!trustedUrl(event.url || url, config.origin)) event.preventDefault();
    });
    contents.on('will-attach-webview', event => event.preventDefault());
    contents.on('did-start-navigation', event => {
      if (event.isMainFrame && !event.isSameDocument) clearNotification();
    });
    contents.on(
      'did-fail-load',
      (_event, code, _description, _url, isMainFrame) => {
        if (isMainFrame && code !== -3) scheduleRecovery();
      }
    );
    contents.on('render-process-gone', () => {
      loading = false;
      scheduleRecovery();
    });
    contents.on('did-finish-load', () => {
      if (!trustedUrl(contents.getURL(), config.origin)) return;
      unavailable = false;
      timers.clearTimeout(recoveryTimer);
      recoveryTimer = undefined;
      timers.clearTimeout(stabilityTimer);
      stabilityTimer = timers.setTimeout(() => {
        recoveryAttempt = 0;
      }, 60000);
      refreshTray();
    });
    mainWindow.once('ready-to-show', showWindow);
    const hideWindow = event => {
      if (quitting) return;
      event.preventDefault();
      mainWindow.hide();
    };
    mainWindow.on('close', hideWindow);
    mainWindow.on('minimize', hideWindow);
    mainWindow.on('focus', () => mainWindow.flashFrame(false));
    // An actually destroyed window has no SIP renderer left to preserve.
    mainWindow.on('closed', () => {
      if (!quitting && !switchingServer) app.quit();
    });
  };

  function showSetup() {
    if (quitting) return;
    if (setupWindow && !setupWindow.isDestroyed()) {
      if (setupWindow.isMinimized()) setupWindow.restore();
      setupWindow.show();
      setupWindow.focus();
      return;
    }
    setupWindow = new BrowserWindow({
      width: 540,
      height: 450,
      minWidth: 400,
      minHeight: 400,
      show: false,
      title: 'Configurações — JRC Softphone',
      autoHideMenuBar: true,
      webPreferences: {
        preload: path.join(__dirname, 'setup-preload.cjs'),
        partition: 'jrc-softphone-settings',
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
        webSecurity: true,
        webviewTag: false,
        devTools: !app.isPackaged,
      },
    });
    setupWindow.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    [
      'will-navigate',
      'will-redirect',
      'will-frame-navigate',
      'will-attach-webview',
    ].forEach(name => {
      setupWindow.webContents.on(name, event => event.preventDefault());
    });
    setupWindow.webContents.session.setPermissionCheckHandler(() => false);
    setupWindow.webContents.session.setPermissionRequestHandler(
      (_wc, _permission, callback) => callback(false)
    );
    setupWindow.once('ready-to-show', () => {
      setupWindow?.show();
      setupWindow?.focus();
    });
    setupWindow.on('close', event => {
      if (!quitting) {
        event.preventDefault();
        setupWindow.hide();
      }
    });
    setupWindow.on('closed', () => {
      setupWindow = undefined;
    });
    setupWindow.loadFile(setupFile).catch(() => {
      dialog.showErrorBox(
        'JRC Softphone',
        'Não foi possível abrir a configuração do servidor.'
      );
    });
  }

  const localSettingsSender = event =>
    Boolean(
      setupWindow &&
        !setupWindow.isDestroyed() &&
        event.sender === setupWindow.webContents &&
        event.senderFrame === setupWindow.webContents.mainFrame &&
        event.senderFrame?.url === pathToFileURL(setupFile).href
    );

  const stopPreviousServer = async () => {
    const previous = mainWindow;
    if (previous && !previous.isDestroyed()) {
      timers.clearTimeout(recoveryTimer);
      timers.clearTimeout(stabilityTimer);
      recoveryTimer = undefined;
      clearNotification();
      floatingWindow?.destroy();
      await new Promise(resolve => {
        const timer = timers.setTimeout(() => {
          pendingServerShutdown = undefined;
          resolve();
        }, 3000);
        pendingServerShutdown = {
          window: previous,
          complete: () => {
            timers.clearTimeout(timer);
            pendingServerShutdown = undefined;
            resolve();
          },
        };
        // Reuse the LAB3 shutdown handshake, not another SIP implementation.
        previous.webContents.send('softphone:floating-command', {
          action: 'shutdown',
        });
      });
      retiredSession = previous.webContents.session;
      // Destruction is mandatory even after ACK. On timeout/crash it also
      // guarantees no previous UserAgent/WebSocket can survive locally.
      previous.destroy();
      mainWindow = undefined;
    }
    latestFloatingState = undefined;
    openedAfterRegistration = false;
    loading = false;
    unavailable = true;
    if (retiredSession) {
      await retiredSession.closeAllConnections();
      await retiredSession.clearStorageData();
      await retiredSession.clearAuthCache();
      await retiredSession.clearCache();
      retiredSession = undefined;
    }
    permitNotification = notificationGate();
    recoveryAttempt = 0;
  };

  const changeServer = async payload => {
    if (quitting || switchingServer)
      return { ok: false, error: 'Aguarde a troca de servidor em andamento.' };
    let origin;
    try {
      if (!payload || Object.keys(payload).length !== 1) throw new Error();
      origin = serverOrigin(payload.url);
    } catch {
      return {
        ok: false,
        error: 'Informe um endereço HTTPS válido, sem usuário ou senha.',
      };
    }
    if (origin === config?.origin && mainWindow && !mainWindow.isDestroyed()) {
      setupWindow?.hide();
      showWindow();
      return { ok: true };
    }
    switchingServer = true;
    refreshTray();
    try {
      await stopPreviousServer();
      if (quitting)
        return { ok: false, error: 'O aplicativo está encerrando.' };
      settings.save(origin);
      config = { origin, url: origin, localDevelopment: false };
      setupError = '';
      configureWindow();
      switchingServer = false;
      setupWindow?.hide();
      await loadWindow();
      showWindow();
      return { ok: true };
    } catch {
      return {
        ok: false,
        error:
          'Não foi possível limpar a sessão anterior ou salvar o servidor. Tente novamente.',
      };
    } finally {
      switchingServer = false;
      refreshTray();
    }
  };
  app.on('second-instance', showWindow);
  // This event has no Event argument. Normal close is intercepted by hideWindow.
  app.on('window-all-closed', () => {});
  const finishQuit = () => {
    if (finalQuit) return;
    finalQuit = true;
    timers.clearTimeout(shutdownTimer);
    app.exit(0);
  };
  app.on('before-quit', event => {
    if (!finalQuit) event?.preventDefault();
    quitting = true;
    timers.clearTimeout(recoveryTimer);
    timers.clearTimeout(stabilityTimer);
    clearNotification();
    tray?.destroy();
    setupWindow?.destroy();
    if (floatingWindow && !floatingWindow.isDestroyed())
      floatingWindow.destroy();
    if (finalQuit) return;
    if (!mainWindow || mainWindow.isDestroyed()) {
      finishQuit();
      return;
    }
    mainWindow?.webContents.send('softphone:floating-command', {
      action: 'shutdown',
    });
    shutdownTimer = timers.setTimeout(finishQuit, 3000);
  });
  app
    .whenReady()
    .then(() => {
      try {
        config = serverConfig({
          argv,
          env,
          isPackaged: app.isPackaged,
          savedOrigin: settings.read(),
        });
        if (config && !config.localDevelopment) settings.save(config.origin);
      } catch (error) {
        config = undefined;
        setupError =
          'Não foi possível usar a configuração anterior. Informe um endereço HTTPS válido.';
      }
      const icon = nativeImage.createFromPath(
        path.join(__dirname, '../assets/tray.png')
      );
      if (icon.isEmpty())
        throw new Error('O ícone da bandeja não pôde ser carregado.');
      tray = new Tray(icon);
      tray.on('click', showWindow);
      if (app.isPackaged) {
        const startup = app.getLoginItemSettings({ path: process.execPath });
        // Older entries included --server-url; openAtLogin requires matching args.
        if (startup.openAtLogin || startup.executableWillLaunchAtLogin)
          app.setLoginItemSettings({ ...loginSettings(), openAtLogin: true });
      }
      if (config) configureWindow();
      refreshTray();
      ipcMain.handle('softphone:server-settings', event => {
        if (!localSettingsSender(event)) return null;
        return { origin: config?.origin || '', error: setupError };
      });
      ipcMain.handle('softphone:set-server', (event, payload) => {
        if (!localSettingsSender(event))
          return { ok: false, error: 'Solicitação não autorizada.' };
        return changeServer(payload);
      });
      ipcMain.on('softphone:incoming-call', (event, payload) => {
        if (
          switchingServer ||
          !trustedSender(event, mainWindow, config?.origin) ||
          !incomingPayload(payload) ||
          !permitNotification(payload.callId)
        )
          return;
        clearNotification();
        pendingCallId = payload.callId;
        mainWindow.flashFrame(true);
        try {
          if (!Notification.isSupported()) {
            showFloatingWindow();
            return;
          }
          notification = new Notification({
            title: 'JRC Softphone',
            body: `Chamada recebida de ${payload.remote}`,
          });
          notification.on('click', showFloatingWindow);
          notification.on('failed', showFloatingWindow);
          notification.show();
          showFloatingWindow();
        } catch {
          showFloatingWindow();
        }
      });
      ipcMain.on('softphone:clear-call', (event, payload) => {
        if (
          trustedSender(event, mainWindow, config?.origin) &&
          clearPayload(payload) &&
          payload.callId === pendingCallId
        )
          clearNotification();
      });
      ipcMain.handle('softphone:open-contact', (event, payload) => {
        if (!trustedSender(event, mainWindow, config?.origin)) return false;
        const url = contactUrl(payload, config.origin);
        return url ? openExternal(url) : false;
      });
      ipcMain.on('softphone:floating-state', (event, payload) => {
        if (
          switchingServer ||
          !trustedSender(event, mainWindow, config?.origin) ||
          !floatingState(payload)
        )
          return;
        const incomingStarted =
          payload.incoming && !latestFloatingState?.incoming;
        const firstRegistration =
          payload.registered && !openedAfterRegistration;
        if (firstRegistration) openedAfterRegistration = true;
        if (!payload.registered && !payload.extension)
          openedAfterRegistration = false;
        latestFloatingState = payload;
        sendFloatingState();
        if (firstRegistration || incomingStarted) showFloatingWindow();
      });
      ipcMain.on('softphone:floating-ready', event => {
        if (
          floatingWindow &&
          !floatingWindow.isDestroyed() &&
          event.sender === floatingWindow.webContents &&
          event.senderFrame === floatingWindow.webContents.mainFrame
        )
          sendFloatingState();
      });
      ipcMain.on('softphone:floating-command', (event, payload) => {
        if (
          switchingServer ||
          !floatingWindow ||
          floatingWindow.isDestroyed() ||
          event.sender !== floatingWindow.webContents ||
          event.senderFrame !== floatingWindow.webContents.mainFrame ||
          !floatingCommand(payload)
        )
          return;
        if (payload.action === 'showMain') showWindow();
        else
          mainWindow?.webContents.send('softphone:floating-command', payload);
      });
      ipcMain.on('softphone:floating-shutdown-complete', event => {
        if (!trustedSender(event, mainWindow, config?.origin)) return;
        if (pendingServerShutdown?.window === mainWindow)
          pendingServerShutdown.complete();
        else if (quitting) finishQuit();
      });
      if (config) loadWindow();
      else showSetup();
    })
    .catch(() => {
      dialog.showErrorBox(
        'JRC Softphone',
        'Não foi possível iniciar. Verifique a URL HTTPS configurada e os arquivos do aplicativo.'
      );
      app.quit();
    });
}
module.exports = { startDesktop };
// Keep native Electron loading at the executable entrypoint so policy/lifecycle tests run in Node.
// eslint-disable-next-line global-require
if (require.main === module) startDesktop(require('electron'));
