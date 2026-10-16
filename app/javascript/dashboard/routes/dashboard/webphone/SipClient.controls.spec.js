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
      onMute: vi.fn(),
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
    ['immediate', '#202'],
    ['supervised', '*1202'],
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
    expect(callbacks.onLog).not.toHaveBeenCalled();
    expect(callbacks.onTransferPending.mock.calls.map(args => args[0])).toEqual(
      [true, false]
    );
  });
  it.each([
    ['immediate', '#1410'],
    ['supervised', '*11410'],
  ])(
    'sends the exact new %s sequence for human extension 1410',
    async (type, expected) => {
      const transfer = client.transfer(type, '1410');
      await vi.runAllTimersAsync();
      await transfer;
      const tones = session.sessionDescriptionHandler.sendDtmf.mock.calls
        .map(args => args[0])
        .join('');
      expect(tones).toBe(expected);
      expect(tones).not.toMatch(/^\*[34]/);
      expect(tones).not.toContain('81410');
    }
  );
  it.each(['', '+1410', '1410#', 'abc', '1410;hangup'])(
    'rejects invalid transfer destination %s without tones',
    async value => {
      await expect(client.transfer('immediate', value)).rejects.toThrow(
        'ramal interno'
      );
      expect(session.sessionDescriptionHandler.sendDtmf).not.toHaveBeenCalled();
    }
  );
  it('rejects an unknown transfer type instead of silently choosing a mode', async () => {
    await expect(client.transfer('unknown', '1410')).rejects.toThrow(
      'Tipo de transferência'
    );
    expect(session.sessionDescriptionHandler.sendDtmf).not.toHaveBeenCalled();
  });
  it.each([null, 'Terminated', 'Establishing'])(
    'requires a valid SIP session %s',
    async state => {
      if (state) session.state = state;
      else client.session = null;
      await expect(client.transfer('supervised', '1410')).rejects.toThrow(
        'chamada estabelecida'
      );
      expect(session.sessionDescriptionHandler.sendDtmf).not.toHaveBeenCalled();
    }
  );
  it('rejects missing media and failed WebRTC without altering the call', async () => {
    session.sessionDescriptionHandler.peerConnection.connectionState = 'failed';
    await expect(client.transfer('immediate', '1410')).rejects.toThrow('mídia');
    expect(session.sessionDescriptionHandler.sendDtmf).not.toHaveBeenCalled();
    expect(client.session).toBe(session);
  });
  it.each(['onReject', 'onRedirect'])(
    'does not report a successful transfer after SIP INFO %s',
    async response => {
      session.sessionDescriptionHandler.sendDtmf.mockReturnValue(false);
      session.info.mockImplementation(async options => {
        options.requestDelegate?.[response]({ message: { statusCode: 403 } });
      });
      const transfer = client.transfer('immediate', '1410');
      const rejected = expect(transfer).rejects.toThrow('DTMF');
      await vi.runAllTimersAsync();
      await rejected;
      expect(session.info).toHaveBeenCalledOnce();
      expect(callbacks.onLog).not.toHaveBeenCalled();
      expect(client.transferInProgress).toBe(false);
      expect(
        callbacks.onTransferPending.mock.calls.map(args => args[0])
      ).toEqual([true, false]);
    }
  );
  it.each([
    ['immediate', '#1410'],
    ['supervised', '*11410'],
  ])(
    'preserves exact %s transfer tones through SIP INFO',
    async (type, expected) => {
      session.sessionDescriptionHandler.sendDtmf.mockReturnValue(false);
      session.info.mockImplementation(async options => {
        options.requestDelegate?.onAccept();
      });
      const transfer = client.transfer(type, '1410');
      await vi.runAllTimersAsync();
      await transfer;
      const tones = session.info.mock.calls.map(
        ([options]) =>
          options.requestOptions.body.content.match(
            /^Signal=(.)\r\nDuration=160$/
          )[1]
      );
      expect(tones).toEqual([...expected]);
      expect(callbacks.onLog).toHaveBeenCalledOnce();
    }
  );
  it('waits for SIP INFO acceptance before advancing to the next tone or reporting success', async () => {
    session.sessionDescriptionHandler.sendDtmf.mockReturnValue(false);
    const transfer = client.transfer('immediate', '1410');
    await vi.runAllTimersAsync();
    expect(session.info).toHaveBeenCalledOnce();
    expect(client.transferInProgress).toBe(true);
    expect(callbacks.onLog).not.toHaveBeenCalled();
    for (let index = 0; index < '#1410'.length; index += 1) {
      session.info.mock.calls[index][0].requestDelegate.onAccept();
      // Each acceptance allows the existing per-tone timer to advance.
      // eslint-disable-next-line no-await-in-loop
      await vi.runAllTimersAsync();
    }
    await transfer;
    expect(callbacks.onLog).toHaveBeenCalledOnce();
    expect(client.transferInProgress).toBe(false);
  });
  it('stops after an INFO transport failure and does not emit success', async () => {
    session.sessionDescriptionHandler.sendDtmf.mockReturnValue(false);
    session.info.mockRejectedValue(new Error('INFO transport failed'));
    await expect(client.transfer('supervised', '1410')).rejects.toThrow(
      'INFO transport failed'
    );
    expect(session.info).toHaveBeenCalledOnce();
    expect(callbacks.onLog).not.toHaveBeenCalled();
    expect(client.transferInProgress).toBe(false);
  });
  it.each(['terminated', 'replaced'])(
    'does not report success when the session is %s during the last tone',
    async change => {
      session.sessionDescriptionHandler.sendDtmf.mockImplementation(tone => {
        if (tone === '0') {
          if (change === 'terminated') session.state = 'Terminated';
          else client.session = { ...session };
        }
        return true;
      });
      const transfer = client.transfer('supervised', '1410');
      const rejected = expect(transfer).rejects.toThrow('encerrada');
      await vi.runAllTimersAsync();
      await rejected;
      expect(callbacks.onLog).not.toHaveBeenCalled();
      expect(client.transferInProgress).toBe(false);
    }
  );
  it('keeps mute and microphone state consistent across accepted hold and resume', async () => {
    client.setMuted(true);
    expect(track.enabled).toBe(false);
    expect(callbacks.onMute).toHaveBeenLastCalledWith(true);
    const hold = client.setHold(true);
    session.invite.mock.calls[0][0].requestDelegate.onAccept();
    await hold;
    client.setMuted(false);
    expect(track.enabled).toBe(false);
    const resume = client.setHold(false);
    session.invite.mock.calls[1][0].requestDelegate.onAccept();
    await resume;
    expect(client.held).toBe(false);
    expect(client.muted).toBe(false);
    expect(track.enabled).toBe(true);
    expect(callbacks.onHold.mock.calls.map(args => args[0])).toEqual([
      true,
      false,
    ]);
  });
  it('prevents transfer while a hold request is pending', async () => {
    const hold = client.setHold(true);
    await expect(client.transfer('immediate', '1410')).rejects.toThrow(
      'Aguarde'
    );
    expect(session.sessionDescriptionHandler.sendDtmf).not.toHaveBeenCalled();
    session.invite.mock.calls[0][0].requestDelegate.onAccept();
    await hold;
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
    session.info.mockImplementation(async options => {
      options.requestDelegate.onAccept();
    });
    await client.sendDtmf('#');
    expect(session.info).toHaveBeenCalledWith({
      requestDelegate: {
        onAccept: expect.any(Function),
        onReject: expect.any(Function),
        onRedirect: expect.any(Function),
      },
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
