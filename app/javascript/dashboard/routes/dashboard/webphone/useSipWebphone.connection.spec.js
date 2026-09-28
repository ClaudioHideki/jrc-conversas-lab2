import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mock = vi.hoisted(() => ({
  callbacks: null,
  connect: vi.fn(),
  disconnect: vi.fn(),
  transfer: vi.fn(),
  call: vi.fn(),
  sendDtmf: vi.fn(),
  clearNotification: vi.fn(),
}));
vi.mock('./SipClient', () => ({
  SipClient: class {
    constructor(callbacks) {
      mock.callbacks = callbacks;
      this.connect = mock.connect;
      this.disconnect = mock.disconnect;
      this.transfer = mock.transfer;
      this.call = mock.call;
      this.sendDtmf = mock.sendDtmf;
    }
  },
}));
vi.mock('dashboard/api/sipCredentials', () => ({
  default: {
    getMine: async () => ({
      data: {
        configured: true,
        enabled: true,
        extension: '101',
        password: 'SYNTHETIC_SECRET',
      },
    }),
  },
}));
vi.mock('./callNotification', () => ({
  notifyIncomingCall: vi.fn(),
  clearIncomingCallNotification: mock.clearNotification,
}));

describe('softphone reconnect coordinator', () => {
  let api;
  beforeEach(async () => {
    vi.resetModules();
    vi.useFakeTimers();
    vi.clearAllMocks();
    window.localStorage.clear();
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(true);
    mock.connect.mockImplementation(async () => {
      mock.callbacks.onRegister('Registered');
    });
    mock.disconnect.mockImplementation(async () => {
      mock.callbacks.onTransport('Desconectado');
      mock.callbacks.onRegister('Não registrado');
    });
    mock.transfer.mockResolvedValue(undefined);
    mock.call.mockResolvedValue(undefined);
    api = (await import('./useSipWebphone')).useSipWebphone();
    await api.initialize(1);
  });
  afterEach(async () => {
    await api.shutdown();
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });
  it('reconnects after Registered to Unregistered without a transport disconnect', async () => {
    mock.callbacks.onRegister('Unregistered');
    expect(api.reconnecting.value).toBe(true);
    await vi.advanceTimersByTimeAsync(999);
    expect(mock.connect).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(mock.connect).toHaveBeenCalledTimes(2);
    expect(api.registered.value).toBe(true);
  });
  it('does not reconnect after voluntary disconnect or logout', async () => {
    await api.disconnect();
    mock.callbacks.onRegister('Unregistered');
    window.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(60000);
    expect(mock.connect).toHaveBeenCalledTimes(1);
    await api.shutdown();
    mock.callbacks.onRegister('Unregistered');
    await vi.advanceTimersByTimeAsync(60000);
    expect(mock.connect).toHaveBeenCalledTimes(1);
  });
  it('does not reconnect when the extension is switched off', async () => {
    await api.turnOffExtension();
    mock.callbacks.onRegister('Unregistered');
    await vi.advanceTimersByTimeAsync(60000);
    expect(mock.connect).toHaveBeenCalledTimes(1);
    expect(
      window.localStorage.getItem('jrc-softphone-extension:1:enabled')
    ).toBe('false');
  });
  it('stops automatic retries for permanent rejection and allows explicit retry', async () => {
    mock.callbacks.onRegister('Unregistered');
    mock.callbacks.onRegistrationFailure({ permanent: true });
    window.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(60000);
    expect(mock.connect).toHaveBeenCalledTimes(1);
    await api.turnOnExtension();
    expect(mock.connect).toHaveBeenCalledTimes(2);
  });
  it('respects Retry-After even when online arrives', async () => {
    mock.callbacks.onRegister('Unregistered', { retryAfterMs: 90000 });
    mock.callbacks.onRegistrationFailure({
      permanent: false,
      retryAfterMs: 90000,
    });
    window.dispatchEvent(new Event('online'));
    await vi.advanceTimersByTimeAsync(89999);
    expect(mock.connect).toHaveBeenCalledTimes(1);
    await vi.advanceTimersByTimeAsync(1);
    expect(mock.connect).toHaveBeenCalledTimes(2);
  });
  it('backs off transient failures instead of looping', async () => {
    mock.connect.mockRejectedValue(new Error('temporary transport failure'));
    mock.callbacks.onTransport('Desconectado');
    await vi.advanceTimersByTimeAsync(1000);
    expect(mock.connect).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1999);
    expect(mock.connect).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1);
    expect(mock.connect).toHaveBeenCalledTimes(3);
  });
  it('keeps a pending REGISTER exclusive and cancels it before retrying after watchdog', async () => {
    let resolveConnection;
    mock.connect.mockImplementation(
      () =>
        new Promise(resolve => {
          resolveConnection = resolve;
        })
    );
    mock.callbacks.onTransport('Desconectado');
    await vi.advanceTimersByTimeAsync(1000);
    await api.connect();
    mock.callbacks.onRegister('Unregistered');
    await vi.advanceTimersByTimeAsync(19999);
    expect(mock.connect).toHaveBeenCalledTimes(2);
    await vi.advanceTimersByTimeAsync(1);
    expect(mock.disconnect).toHaveBeenCalledOnce();
    resolveConnection();
    await Promise.resolve();
    await api.turnOffExtension();
  });
  it('returns failure to the transfer UI instead of treating swallowed errors as success', async () => {
    mock.transfer.mockRejectedValue(new Error('transfer failed'));
    await expect(api.transferCall('supervised', '202')).resolves.toBe(false);
    expect(api.errorMessage.value).toBe('transfer failed');
    mock.transfer.mockResolvedValue(undefined);
    await expect(api.transferCall('immediate', '202')).resolves.toBe(true);
  });
  it('does not send another transfer or keypad tones while a transfer is pending', async () => {
    mock.callbacks.onTransferPending(true);
    mock.callbacks.onEstablished();
    await expect(api.transferCall('supervised', '202')).resolves.toBe(false);
    await api.pressKey('5');
    expect(mock.transfer).not.toHaveBeenCalled();
    expect(mock.sendDtmf).not.toHaveBeenCalled();
  });
  it.each([
    ['NotAllowedError', 'negado'],
    ['NotFoundError', 'Nenhum microfone'],
    ['NotReadableError', 'indisponível'],
  ])('explains microphone failure %s', async (name, expected) => {
    mock.call.mockRejectedValue(
      Object.assign(new Error('browser detail'), { name })
    );
    await api.call();
    expect(api.errorMessage.value).toContain(expected);
  });
  it('clears call notifications on answer and end', () => {
    mock.callbacks.onEstablished();
    mock.callbacks.onEnded();
    expect(mock.clearNotification).toHaveBeenCalledTimes(2);
  });
});
