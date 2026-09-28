const notificationTitle = 'JRC Softphone';

let activeCallId;
let browserNotification;

export const clearIncomingCallNotification = () => {
  const callId = activeCallId;
  activeCallId = undefined;
  try {
    browserNotification?.close();
  } catch {
    // Notification failures must never change SIP call processing.
  }
  browserNotification = undefined;
  try {
    if (callId) {
      Promise.resolve(
        window.jrcSoftphoneDesktop?.clearIncomingCall?.({ callId })
      ).catch(() => {});
    }
  } catch {
    // The desktop may be closing while SIP reports the end of a call.
  }
};

export const notificationPermission = () => {
  try {
    return window.jrcSoftphoneDesktop || !('Notification' in window)
      ? 'unavailable'
      : Notification.permission;
  } catch {
    return 'unavailable';
  }
};

// Only called by the explicit enable-notifications button, never by a SIP event.
export const requestCallNotificationPermission = async () => {
  const permission = notificationPermission();
  if (
    permission !== 'default' ||
    navigator.userActivation?.isActive === false
  ) {
    return permission;
  }
  try {
    return await Notification.requestPermission();
  } catch {
    return 'denied';
  }
};

export const shouldNotifyIncomingCall = () =>
  typeof document !== 'undefined' && document.visibilityState !== 'visible';

export const notifyIncomingCall = ({ remote, callId }) => {
  if (!callId || activeCallId === callId) return;
  clearIncomingCallNotification();
  activeCallId = callId;
  try {
    const caller = String(remote || 'número não identificado');
    const desktop = window.jrcSoftphoneDesktop;
    if (typeof desktop?.incomingCall === 'function') {
      Promise.resolve(desktop.incomingCall({ callId, remote: caller })).catch(
        () => {}
      );
      return;
    }
    if (!shouldNotifyIncomingCall() || notificationPermission() !== 'granted') {
      return;
    }
    browserNotification = new Notification(notificationTitle, {
      body: `Chamada recebida de ${caller}`,
      tag: 'jrc-softphone-incoming',
    });
    browserNotification.onclick = () => {
      if (activeCallId === callId) window.focus();
    };
  } catch {
    // A notification is optional; the incoming SIP session is not.
  }
};
