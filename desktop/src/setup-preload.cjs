const { contextBridge, ipcRenderer } = require('electron');

// Available only in the local provisioning window, never in remote JRC content.
contextBridge.exposeInMainWorld('jrcServerSettings', {
  read: () => ipcRenderer.invoke('softphone:server-settings'),
  connect: url => ipcRenderer.invoke('softphone:set-server', { url }),
});
