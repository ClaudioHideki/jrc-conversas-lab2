const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('jrcSoftphoneDesktop', {
  incomingCall: payload => ipcRenderer.send('softphone:incoming-call', payload),
  clearIncomingCall: payload =>
    ipcRenderer.send('softphone:clear-call', payload),
  openContact: payload => ipcRenderer.invoke('softphone:open-contact', payload),
  sendFloatingState: payload =>
    ipcRenderer.send('softphone:floating-state', payload),
  requestFloatingState: () => ipcRenderer.send('softphone:floating-ready'),
  sendFloatingShutdownComplete: () =>
    ipcRenderer.send('softphone:floating-shutdown-complete'),
  onFloatingCommand: callback => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on('softphone:floating-command', listener);
    return () =>
      ipcRenderer.removeListener('softphone:floating-command', listener);
  },
  sendFloatingCommand: payload =>
    ipcRenderer.send('softphone:floating-command', payload),
  onFloatingState: callback => {
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on('softphone:floating-state', listener);
    return () =>
      ipcRenderer.removeListener('softphone:floating-state', listener);
  },
});
