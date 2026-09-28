/* eslint max-classes-per-file: off, class-methods-use-this: off */
const { EventEmitter } = require('node:events');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { startDesktop } = require('../src/main.cjs');

// Test the actual main-process handlers without starting Electron or touching userData.
function harness({
  lock = true,
  isPackaged = true,
  emptyIcon = false,
  failLoad = false,
  argv = ['electron', '--server-url=https://jrc.example/app?mode=a=b'],
  env = {},
  files = new Map(),
  savedOrigin,
  savedText,
  failSave = false,
  failCleanup = false,
  legacyAutostart = false,
} = {}) {
  const windows = [];
  const notices = [];
  const opened = [];
  const saved = [];
  const errors = [];
  const pendingTimers = new Map();
  const reads = [];
  const lifecycle = [];
  const paths = {
    appData: path.resolve('/mock-app-data'),
    userData: path.resolve('/old-default'),
  };
  const configPath = path.join(
    paths.appData,
    'JRC Softphone',
    'softphone-server.json'
  );
  if (savedOrigin !== undefined)
    files.set(configPath, JSON.stringify({ origin: savedOrigin }));
  if (savedText !== undefined) files.set(configPath, savedText);
  let timerId = 0;
  const app = new EventEmitter();
  Object.assign(app, {
    isPackaged,
    quits: 0,
    readyCalls: 0,
    requestSingleInstanceLock: () => lock,
    setAppUserModelId: id => {
      app.appId = id;
    },
    whenReady: () => {
      app.readyCalls += 1;
      return Promise.resolve();
    },
    quit: () => {
      app.quits += 1;
      app.emit('before-quit');
    },
    exit: () => {
      app.exits = (app.exits || 0) + 1;
    },
    getPath: name => paths[name],
    setPath: (name, value) => {
      paths[name] = value;
    },
    getLoginItemSettings: () => ({
      openAtLogin: false,
      executableWillLaunchAtLogin: legacyAutostart,
    }),
    setLoginItemSettings: settings => {
      app.loginSettings = settings;
    },
  });
  class Window extends EventEmitter {
    constructor(options) {
      super();
      this.options = options;
      this.actions = [];
      this.minimized = false;
      this.webContents = new EventEmitter();
      Object.assign(this.webContents, {
        mainFrame: { url: 'https://jrc.example/app' },
        getURL: () => this.webContents.mainFrame.url,
        send: (...args) => {
          this.webContents.sent = [...(this.webContents.sent || []), args];
        },
        setWindowOpenHandler: handler => {
          this.openHandler = handler;
        },
        session: {
          clearAuthCache: async () => {
            lifecycle.push('clearAuth');
          },
          closeAllConnections: async () => {
            lifecycle.push('closeConnections');
          },
          clearStorageData: async () => {
            lifecycle.push('clearStorage');
            if (failCleanup) throw new Error('cleanup failed');
          },
          clearCache: async () => {
            lifecycle.push('clearCache');
          },
          setPermissionCheckHandler: handler => {
            this.checkPermission = handler;
          },
          setPermissionRequestHandler: handler => {
            this.requestPermission = handler;
          },
        },
      });
      windows.push(this);
    }

    isDestroyed() {
      return Boolean(this.destroyed);
    }

    destroy() {
      this.destroyed = true;
      lifecycle.push(`destroy:${windows.indexOf(this)}`);
      this.emit('closed');
    }

    isMinimized() {
      return this.minimized;
    }

    restore() {
      this.minimized = false;
      this.actions.push('restore');
    }

    show() {
      this.actions.push('show');
    }

    focus() {
      this.actions.push('focus');
    }

    hide() {
      this.actions.push('hide');
    }

    flashFrame(value) {
      this.flash = value;
    }

    async loadURL(url) {
      this.loads = (this.loads || 0) + 1;
      this.loadedUrl = url;
      this.webContents.mainFrame.url = url;
      lifecycle.push(`load:${url}`);
      if (failLoad) throw new Error('secret URL must not reach logs');
    }

    async loadFile(file) {
      this.loadedFile = file;
      this.webContents.mainFrame.url = pathToFileURL(file).href;
    }
  }
  class Notice extends EventEmitter {
    constructor(options) {
      super();
      this.options = options;
      notices.push(this);
    }

    static isSupported() {
      return true;
    }

    show() {
      this.shown = true;
    }

    close() {
      this.closed = true;
    }
  }
  class Tray extends EventEmitter {
    constructor() {
      super();
      app.tray = this;
    }

    setToolTip(value) {
      this.tooltip = value;
    }

    setContextMenu(menu) {
      this.menu = menu;
    }

    destroy() {
      this.destroyed = true;
    }
  }
  const ipcMain = new EventEmitter();
  ipcMain.handle = (channel, handler) => {
    ipcMain[channel] = handler;
  };
  const electron = {
    app,
    BrowserWindow: Window,
    Notification: Notice,
    Tray,
    ipcMain,
    Menu: { buildFromTemplate: items => items },
    nativeImage: { createFromPath: () => ({ isEmpty: () => emptyIcon }) },
    shell: {
      openExternal: async url => {
        opened.push(url);
      },
    },
    dialog: { showErrorBox: (...args) => errors.push(args) },
  };
  const options = {
    argv,
    env,
    fileSystem: {
      mkdirSync: () => {},
      readFileSync: file => {
        reads.push(file);
        if (files.has(file)) return files.get(file);
        const error = new Error();
        error.code = 'ENOENT';
        throw error;
      },
      writeFileSync: (file, data) => {
        if (failSave) throw new Error('write denied');
        files.set(file, data);
      },
      renameSync: (from, to) => {
        files.set(to, files.get(from));
        files.delete(from);
        saved.push(JSON.parse(files.get(to)));
        lifecycle.push('save');
      },
    },
    timers: {
      setTimeout: (callback, delay) => {
        timerId += 1;
        const id = timerId;
        pendingTimers.set(id, { callback, delay });
        return id;
      },
      clearTimeout: id => pendingTimers.delete(id),
    },
  };
  startDesktop(electron, options);
  return {
    app,
    windows,
    notices,
    ipcMain,
    opened,
    saved,
    errors,
    pendingTimers,
    files,
    configPath,
    reads,
    lifecycle,
  };
}

module.exports = { harness };
