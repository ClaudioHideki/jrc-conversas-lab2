import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { Invitation, Inviter, SessionState, UserAgent } from 'sip.js';
import { SipClient } from './SipClient';

vi.mock('sip.js', () => {
  function MockInvitation() {
    this.state = 'Initial';
    this.reject = vi.fn().mockResolvedValue(undefined);
  }

  function MockInviter() {
    this.state = 'Initial';
    this.cancel = vi.fn().mockResolvedValue(undefined);
    this.bye = vi.fn().mockResolvedValue(undefined);
    this.stateChange = {
      addListener: listener => {
        this.onState = listener;
      },
    };
    this.invite = vi.fn(async ({ requestDelegate }) => {
      this.requestDelegate = requestDelegate;
    });
  }

  return {
    Invitation: MockInvitation,
    Inviter: MockInviter,
    Registerer: function Registerer() {},
    RegistererState: { Registered: 'Registered' },
    SessionState: {
      Initial: 'Initial',
      Establishing: 'Establishing',
      Established: 'Established',
      Terminating: 'Terminating',
      Terminated: 'Terminated',
    },
    UserAgent: Object.assign(function MockUserAgent() {}, {
      makeURI: vi.fn(value => ({ toString: () => value })),
    }),
  };
});

describe('SipClient call lifecycle', () => {
  let client;

  beforeEach(() => {
    client = new SipClient();
    vi.stubGlobal(
      'MediaStream',
      class {
        constructor() {
          this.getTracks = () => [];
        }
      }
    );
  });
  afterEach(() => vi.unstubAllGlobals());

  it('preserves the SIP rejection code after termination instead of replacing it with a generic failure', async () => {
    const onError = vi.fn();
    client.callbacks.onError = onError;
    client.transportConnected = true;
    client.registerer = { state: 'Registered' };
    client.configuration = { sip_domain: 'pbx.example.test', extension: '100' };
    await client.call('15550000001');
    expect(UserAgent.makeURI).toHaveBeenCalledWith(
      'sip:15550000001@pbx.example.test'
    );
    const session = client.session;
    session.requestDelegate.onReject({
      message: { statusCode: 403, reasonPhrase: 'Forbidden' },
    });
    session.state = SessionState.Terminated;
    session.onState(SessionState.Terminated);
    expect(onError.mock.calls).toEqual([['O PABX recusou a chamada (403).']]);
    expect(client.session).toBeNull();
  });

  it('preserves the rejection in the actual sip.js order: Terminated before the request delegate', async () => {
    const onError = vi.fn();
    client.callbacks.onError = onError;
    client.transportConnected = true;
    client.registerer = { state: 'Registered' };
    client.configuration = { sip_domain: 'pbx.example.test', extension: '100' };
    await client.call('15550000001');
    const session = client.session;
    session.state = SessionState.Terminated;
    session.onState(SessionState.Terminated);
    session.requestDelegate.onReject({ message: { statusCode: 403 } });
    await Promise.resolve();
    expect(onError.mock.calls).toEqual([['O PABX recusou a chamada (403).']]);
  });

  it('does not label an intentional CANCEL followed by 487 as a PBX failure', async () => {
    const onError = vi.fn();
    client.callbacks.onError = onError;
    client.transportConnected = true;
    client.registerer = { state: 'Registered' };
    client.configuration = { sip_domain: 'pbx.example.test', extension: '100' };
    await client.call('15550000001');
    const session = client.session;
    session.state = SessionState.Establishing;
    await client.hangup();
    session.state = SessionState.Terminated;
    session.onState(SessionState.Terminated);
    session.requestDelegate.onReject({ message: { statusCode: 487 } });
    await Promise.resolve();
    expect(onError).not.toHaveBeenCalled();
  });

  it('ignores a late rejection from the previous session after another call has started', async () => {
    const onError = vi.fn();
    client.callbacks.onError = onError;
    client.transportConnected = true;
    client.registerer = { state: 'Registered' };
    client.configuration = { sip_domain: 'pbx.example.test', extension: '100' };
    await client.call('15550000001');
    const previous = client.session;
    previous.state = SessionState.Establishing;
    await client.hangup();
    previous.state = SessionState.Terminated;
    previous.onState(SessionState.Terminated);
    await client.call('15550000002');
    const current = client.session;
    previous.requestDelegate.onReject({ message: { statusCode: 403 } });
    await Promise.resolve();
    expect(onError).not.toHaveBeenCalled();
    expect(client.session).toBe(current);
  });

  it('cancels an outgoing call that has not been established', async () => {
    const session = new Inviter();
    session.state = SessionState.Establishing;
    client.session = session;

    await client.hangup();

    expect(session.cancel).toHaveBeenCalledOnce();
    expect(session.bye).not.toHaveBeenCalled();
  });

  it('sends BYE only for an established call', async () => {
    const session = new Inviter();
    session.state = SessionState.Established;
    client.session = session;

    await client.hangup();

    expect(session.bye).toHaveBeenCalledOnce();
    expect(session.cancel).not.toHaveBeenCalled();
  });

  it('rejects an incoming call without unregistering the extension', async () => {
    const session = new Invitation();
    client.session = session;

    await client.hangup();

    expect(session.reject).toHaveBeenCalledWith({ statusCode: 480 });
    expect(client.session).toBe(session);
  });

  it('blocks a second call while the first call is being created', async () => {
    client.transportConnected = true;
    client.registerer = { state: 'Registered' };
    client.callStarting = true;

    await expect(client.call('100')).rejects.toThrow(
      'Já existe uma chamada ativa'
    );
  });
});
