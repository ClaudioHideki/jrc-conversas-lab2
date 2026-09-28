/* eslint max-classes-per-file: off */
// SIP library fakes share the same fixture and response callbacks.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SipClient } from './SipClient';

const instances = vi.hoisted(() => ({ agents: [], registerers: [] }));
vi.mock('sip.js', () => ({
  Invitation: class {},
  Inviter: class {},
  SessionState: { Established: 'Established', Terminated: 'Terminated' },
  RegistererState: {
    Registered: 'Registered',
    Unregistered: 'Unregistered',
    Terminated: 'Terminated',
  },
  UserAgent: class {
    constructor(options) {
      this.options = options;
      instances.agents.push(this);
    }

    static makeURI(value) {
      return value;
    }

    async start() {
      this.options.delegate.onConnect();
    }

    async stop() {
      this.stopped = true;
    }
  },
  Registerer: class {
    constructor() {
      this.requests = [];
      this.state = 'Initial';
      this.stateChange = {
        addListener: callback => {
          this.listener = callback;
        },
      };
      instances.registerers.push(this);
    }

    async register(options) {
      this.requests.push(options);
    }

    async unregister() {
      this.state = 'Unregistered';
      this.listener(this.state);
    }
  },
}));

describe('SIP confirmed controls and registration', () => {
  let client;
  let track;
  let session;
  let callbacks;
  let errorLog;
  beforeEach(() => {
    vi.useFakeTimers();
    instances.agents.length = 0;
    instances.registerers.length = 0;
    vi.spyOn(console, 'info').mockImplementation(() => {});
    errorLog = vi.spyOn(console, 'error').mockImplementation(() => {});
    callbacks = {
      onHold: vi.fn(),
      onHoldPending: vi.fn(),
      onTransferPending: vi.fn(),
      onRegister: vi.fn(),
      onRegistrationFailure: vi.fn(),
      onLog: vi.fn(),
    };
    client = new SipClient(callbacks);
    track = { kind: 'audio', enabled: true, stop: vi.fn() };
    session = {
      state: 'Established',
      invite: vi.fn().mockResolvedValue(undefined),
      info: vi.fn().mockResolvedValue(undefined),
      sessionDescriptionHandler: {
        sendDtmf: vi.fn().mockReturnValue(true),
        peerConnection: {
          getSenders: () => [{ track }],
          getReceivers: () => [],
        },
      },
    };
    client.session = session;
  });
  afterEach(() => {
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('waits for SIP acceptance before holding and rejects a concurrent re-INVITE', async () => {
    const hold = client.setHold(true);
    expect(client.held).toBe(false);
    expect(track.enabled).toBe(true);
    await expect(client.setHold(true)).rejects.toThrow('Aguarde');
    expect(session.invite).toHaveBeenCalledOnce();
    session.invite.mock.calls[0][0].requestDelegate.onAccept();
    await hold;
    expect(client.held).toBe(true);
    expect(track.enabled).toBe(false);
    expect(callbacks.onHold).toHaveBeenCalledWith(true);
  });
  it('leaves confirmed state/tracks unchanged after rejected resume', async () => {
    client.held = true;
    track.enabled = false;
    const resume = client.setHold(false);
    const rejected = expect(resume).rejects.toThrow('PABX recusou');
    session.invite.mock.calls[0][0].requestDelegate.onReject({
      message: { statusCode: 488 },
    });
    await rejected;
    expect(client.held).toBe(true);
    expect(track.enabled).toBe(false);
    expect(callbacks.onHold).not.toHaveBeenCalled();
    expect(client.holdPending).toBe(false);
  });
  it('releases a pending hold when the call ends', async () => {
    const hold = client.setHold(true);
    const rejected = expect(hold).rejects.toThrow('encerrada');
    client.finishCall();
    await rejected;
    expect(client.holdPending).toBe(false);
  });
  it('releases hold guard after send failure', async () => {
    session.invite.mockRejectedValue(new Error('send failure'));
    await expect(client.setHold(true)).rejects.toThrow('send failure');
    expect(client.holdPending).toBe(false);
    expect(track.enabled).toBe(true);
  });
  it.each([
    ['immediate', '*3202#'],
    ['supervised', '*4202#'],
  ])(
    'preserves %s transfer sequence and prevents concurrent sends',
    async (type, expected) => {
      const transfer = client.transfer(type, '202');
      await expect(client.transfer(type, '303')).rejects.toThrow('Aguarde');
      await expect(client.setHold(true)).rejects.toThrow('Aguarde');
      await vi.runAllTimersAsync();
      await transfer;
      expect(
        session.sessionDescriptionHandler.sendDtmf.mock.calls
          .map(args => args[0])
          .join('')
      ).toBe(expected);
      expect(client.transferInProgress).toBe(false);
    }
  );
  it('propagates transfer failure and releases its guard', async () => {
    session.sessionDescriptionHandler.sendDtmf.mockImplementation(() => {
      throw new Error('DTMF failed');
    });
    await expect(client.transfer('supervised', '202')).rejects.toThrow(
      'DTMF failed'
    );
    expect(client.transferInProgress).toBe(false);
    expect(callbacks.onTransferPending.mock.calls.map(args => args[0])).toEqual(
      [true, false]
    );
  });
  it('does not continue an old sequence into a replacement call', async () => {
    const transfer = client.transfer('immediate', '202');
    const rejected = expect(transfer).rejects.toThrow('encerrada');
    client.session = { ...session };
    await vi.runAllTimersAsync();
    await rejected;
    expect(session.sessionDescriptionHandler.sendDtmf).toHaveBeenCalledTimes(1);
  });
  it('sends all keypad tones through RTP and uses INFO when RTP is unavailable', async () => {
    await Promise.all([...'0123456789*#'].map(tone => client.sendDtmf(tone)));
    expect(
      session.sessionDescriptionHandler.sendDtmf.mock.calls
        .map(args => args[0])
        .join('')
    ).toBe('0123456789*#');
    session.sessionDescriptionHandler.sendDtmf.mockReturnValue(false);
    await client.sendDtmf('#');
    expect(session.info).toHaveBeenCalledWith({
      requestOptions: {
        body: {
          contentDisposition: 'render',
          contentType: 'application/dtmf-relay',
          content: 'Signal=#\r\nDuration=160',
        },
      },
    });
  });
  it('does not resolve connect until the final REGISTER succeeds', async () => {
    client.session = null;
    let resolved = false;
    const connection = client
      .connect({
        extension: '101',
        sip_domain: 'example.test',
        username: '101',
        password: 'SYNTHETIC_SECRET',
      })
      .then(() => {
        resolved = true;
      });
    await Promise.resolve();
    await Promise.resolve();
    expect(resolved).toBe(false);
    const registerer = instances.registerers[0];
    registerer.state = 'Registered';
    registerer.listener('Registered');
    registerer.requests[0].requestDelegate.onAccept();
    await connection;
    expect(resolved).toBe(true);
  });
  it('observes permanent rejection on automatic REGISTER refreshes, not just first registration', async () => {
    client.session = null;
    const connection = client.connect({
      extension: '101',
      sip_domain: 'example.test',
      username: '101',
      password: 'SYNTHETIC_SECRET',
    });
    await Promise.resolve();
    const registerer = instances.registerers[0];
    registerer.requests[0].requestDelegate.onAccept();
    await connection;
    await registerer.register();
    registerer.requests[1].requestDelegate.onReject({
      message: { statusCode: 403, getHeader: () => undefined },
    });
    expect(callbacks.onRegistrationFailure).toHaveBeenCalledWith({
      permanent: true,
      retryAfterMs: 0,
    });
  });
  it('forwards Retry-After for transient refresh rejection', async () => {
    client.session = null;
    const connection = client.connect({
      extension: '101',
      sip_domain: 'example.test',
      username: '101',
      password: 'SYNTHETIC_SECRET',
    });
    await Promise.resolve();
    const registerer = instances.registerers[0];
    registerer.requests[0].requestDelegate.onAccept();
    await connection;
    await registerer.register();
    registerer.retryAfter = 120;
    registerer.listener('Unregistered');
    registerer.requests[1].requestDelegate.onReject({
      message: { statusCode: 503, getHeader: () => '120' },
    });
    expect(callbacks.onRegister).toHaveBeenCalledWith('Unregistered', {
      retryAfterMs: 120000,
    });
    expect(callbacks.onRegistrationFailure).toHaveBeenCalledWith({
      permanent: false,
      retryAfterMs: 120000,
    });
  });
  it('cancels pending REGISTER and ignores its late response after logout', async () => {
    client.session = null;
    const connection = client.connect({
      extension: '101',
      sip_domain: 'example.test',
      username: '101',
      password: 'SYNTHETIC_SECRET',
    });
    const rejected = expect(connection).rejects.toThrow('cancelado');
    await Promise.resolve();
    const registerer = instances.registerers[0];
    await client.disconnect();
    await rejected;
    callbacks.onRegister.mockClear();
    registerer.requests[0].requestDelegate.onAccept();
    expect(callbacks.onRegister).not.toHaveBeenCalled();
    expect(instances.agents[0].stopped).toBe(true);
    expect(client.configuration).toBeNull();
  });
  it('does not expose credentials, auth headers or raw error objects in logs', () => {
    client.configuration = {
      password: 'SYNTHETIC_SECRET',
      username: 'SYNTHETIC_USER',
    };
    client.log(
      'ERRO SIP',
      'Failure SYNTHETIC_SECRET SYNTHETIC_USER Authorization: Bearer SYNTHETIC_TOKEN',
      {
        password: 'SYNTHETIC_SECRET',
        headers: { Cookie: 'SYNTHETIC_COOKIE' },
      }
    );
    const output = JSON.stringify([
      callbacks.onLog.mock.calls,
      errorLog.mock.calls,
    ]);
    expect(output).not.toMatch(/SYNTHETIC_(SECRET|USER|TOKEN|COOKIE)/);
    expect(output).toContain('[REDACTED]');
  });
});
