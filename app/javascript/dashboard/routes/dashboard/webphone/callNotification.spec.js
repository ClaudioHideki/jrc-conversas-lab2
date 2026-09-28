import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  clearIncomingCallNotification,
  notifyIncomingCall,
  requestCallNotificationPermission,
} from './callNotification';

describe('incoming call notifications', () => {
  let notification;
  let close;
  beforeEach(() => {
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
    close = vi.fn();
    notification = vi.fn(function BrowserNotification() {
      this.close = close;
    });
    notification.permission = 'granted';
    notification.requestPermission = vi.fn().mockResolvedValue('granted');
    vi.stubGlobal('Notification', notification);
  });
  afterEach(() => {
    clearIncomingCallNotification();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });
  it('notifies a background call only once', () => {
    notifyIncomingCall({ remote: '123', callId: 'a' });
    notifyIncomingCall({ remote: '123', callId: 'a' });
    expect(notification).toHaveBeenCalledOnce();
    expect(notification).toHaveBeenCalledWith(
      'JRC Softphone',
      expect.objectContaining({ body: 'Chamada recebida de 123' })
    );
  });
  it('does not notify a visible browser page', () => {
    vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('visible');
    notifyIncomingCall({ remote: '123', callId: 'a' });
    expect(notification).not.toHaveBeenCalled();
  });
  it('never requests permission from an incoming SIP event', () => {
    notification.permission = 'default';
    notifyIncomingCall({ remote: '123', callId: 'a' });
    expect(notification.requestPermission).not.toHaveBeenCalled();
    expect(notification).not.toHaveBeenCalled();
  });
  it('contains a constructor exception without interrupting SIP', () => {
    notification.mockImplementation(() => {
      throw new Error('Notification unavailable');
    });
    expect(() =>
      notifyIncomingCall({ remote: '123', callId: 'a' })
    ).not.toThrow();
  });
  it('contains rejected explicit permission requests', async () => {
    notification.permission = 'default';
    notification.requestPermission.mockRejectedValue(new Error('denied'));
    await expect(requestCallNotificationPermission()).resolves.toBe('denied');
  });
  it('contains synchronous permission errors', async () => {
    notification.permission = 'default';
    notification.requestPermission.mockImplementation(() => {
      throw new Error('blocked');
    });
    await expect(requestCallNotificationPermission()).resolves.toBe('denied');
  });
  it('does not display a stale call after delayed permission approval', async () => {
    notification.permission = 'default';
    let grant;
    notification.requestPermission.mockImplementation(
      () =>
        new Promise(resolve => {
          grant = resolve;
        })
    );
    const request = requestCallNotificationPermission();
    notifyIncomingCall({ remote: '123', callId: 'ended' });
    clearIncomingCallNotification();
    grant('granted');
    await request;
    expect(notification).not.toHaveBeenCalled();
  });
  it('closes the notification when a call is answered or ended', () => {
    notifyIncomingCall({ remote: '123', callId: 'a' });
    clearIncomingCallNotification();
    expect(close).toHaveBeenCalledOnce();
  });
  it('uses only Electron and clears the matching call', () => {
    const desktop = { incomingCall: vi.fn(), clearIncomingCall: vi.fn() };
    vi.stubGlobal('jrcSoftphoneDesktop', desktop);
    notifyIncomingCall({ remote: '123', callId: 'a' });
    expect(desktop.incomingCall).toHaveBeenCalledWith({
      remote: '123',
      callId: 'a',
    });
    expect(notification).not.toHaveBeenCalled();
    clearIncomingCallNotification();
    expect(desktop.clearIncomingCall).toHaveBeenCalledWith({ callId: 'a' });
  });
  it.each(['throw', 'reject'])(
    'contains desktop bridge failure: %s',
    async mode => {
      vi.stubGlobal('jrcSoftphoneDesktop', {
        incomingCall: () => {
          if (mode === 'throw') throw new Error('bridge unavailable');
          return Promise.reject(new Error('bridge rejected'));
        },
      });
      expect(() =>
        notifyIncomingCall({ remote: '123', callId: 'a' })
      ).not.toThrow();
      await Promise.resolve();
      expect(notification).not.toHaveBeenCalled();
    }
  );
});
