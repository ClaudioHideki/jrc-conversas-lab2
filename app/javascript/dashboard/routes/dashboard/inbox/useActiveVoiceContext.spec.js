import { describe, expect, it, vi } from 'vitest';
import { resolveVoiceAttendance } from './useActiveVoiceContext';

const identity = {
  accountId: 7,
  provider: 'jrc_pabx',
  sessionId: 'synthetic-session-a',
};
const record = {
  id: 9,
  provider: 'jrc_pabx',
  external_session_id: identity.sessionId,
};

describe('authorized active SIP attendance lookup', () => {
  it('reads an exact scoped server session before exposing customer or note identity', async () => {
    const api = {
      calls: vi
        .fn()
        .mockResolvedValue({ data: { account_id: '7', items: [record] } }),
      call: vi.fn().mockResolvedValue({
        data: {
          account_id: '7',
          item: {
            ...record,
            customer: { status: 'unidentified', contacts: [] },
          },
        },
      }),
    };
    const result = await resolveVoiceAttendance(identity, api);
    expect(api.calls).toHaveBeenCalledWith(7, {
      external_session_id: identity.sessionId,
      provider: 'jrc_pabx',
      limit: 2,
    });
    expect(api.call).toHaveBeenCalledWith(7, 9);
    expect(result.status).toBe('linked');
    expect(result.record.id).toBe(9);
  });

  it('keeps a missing journal record pending and never creates an attendance from browser claims', async () => {
    const api = {
      calls: vi
        .fn()
        .mockResolvedValue({ data: { account_id: '7', items: [] } }),
      call: vi.fn(),
    };
    expect((await resolveVoiceAttendance(identity, api)).status).toBe(
      'pending'
    );
    expect(api.call).not.toHaveBeenCalled();
  });

  it('does not pick the first of multiple records', async () => {
    const api = {
      calls: vi.fn().mockResolvedValue({
        data: { account_id: '7', items: [record, { ...record, id: 10 }] },
      }),
      call: vi.fn(),
    };
    expect((await resolveVoiceAttendance(identity, api)).status).toBe(
      'ambiguous'
    );
    expect(api.call).not.toHaveBeenCalled();
  });

  it('rejects a response from another account or another session', async () => {
    const api = {
      calls: vi
        .fn()
        .mockResolvedValue({ data: { account_id: '8', items: [record] } }),
      call: vi.fn(),
    };
    await expect(resolveVoiceAttendance(identity, api)).rejects.toThrow(
      'voice_context_identity_mismatch'
    );
    api.calls.mockResolvedValue({
      data: {
        account_id: '7',
        items: [{ ...record, external_session_id: 'other-session' }],
      },
    });
    await expect(resolveVoiceAttendance(identity, api)).rejects.toThrow(
      'voice_context_identity_mismatch'
    );
    expect(api.call).not.toHaveBeenCalled();
  });
});
