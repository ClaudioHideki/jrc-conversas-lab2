import { saveAssigneeConfiguration } from './assigneeConfiguration';

const context = { available: true, account_id: '1' };
const recipient = { id: '21', user_id: '31' };
const attributes = {
  active: true,
  availability: 'available',
  capacity: 3,
  skills: [],
  team_id: null,
  queue_id: null,
  manual_assignment_enabled: true,
  restricted_supervision: false,
  supervision_grants: [],
};
const record = {
  ...attributes,
  id: '41',
  unit_id: '14',
  account_user_id: recipient.id,
  account_id: context.account_id,
  revision: 'a'.repeat(64),
};
const payload = (enabled, membership = record) => ({
  contract_version: 1,
  account_id: context.account_id,
  items: [{ ...recipient, auto_assignment_enabled: enabled, membership }],
});
let api;
let calls;
let options;

beforeEach(() => {
  calls = [];
  api = {
    automatic: vi.fn(async (account, user, enabled) => {
      calls.push(enabled ? 'enable' : 'disable');
    }),
    save: vi.fn(async () => calls.push('membership')),
    member: vi.fn(async () => {
      calls.push('readback');
      return payload(false);
    }),
  };
  options = {
    api,
    context,
    recipient,
    unitId: '14',
    intent: { action: 'update', resource: 'unit_memberships', attributes },
    key: 'synthetic-assignee',
    automaticEnabled: false,
    originalAutomatic: true,
    canManageAutomatic: true,
    isCurrent: () => true,
  };
});

describe('Operational membership and native automatic assignment save', () => {
  it('disables the account flag before saving an available membership and rereads both states', async () => {
    const result = await saveAssigneeConfiguration(options);
    expect(calls).toEqual(['disable', 'membership', 'readback']);
    expect(api.member).toHaveBeenCalledWith('1', '14', '21');
    expect(result.error).toBeUndefined();
    expect(result.member.auto_assignment_enabled).toBe(false);
    expect(result.record.manual_assignment_enabled).toBe(true);
  });

  it('does not activate a membership when disabling automatic assignment fails', async () => {
    api.automatic.mockRejectedValue(new Error('Synthetic disable failure'));
    api.member.mockResolvedValue(payload(true, null));
    const result = await saveAssigneeConfiguration(options);
    expect(api.save).not.toHaveBeenCalled();
    expect(api.member).toHaveBeenCalledOnce();
    expect(result.error.message).toBe('Synthetic disable failure');
    expect(result.member.auto_assignment_enabled).toBe(true);
    expect(result.record).toBeNull();
  });

  it('retains the disabled flag and returns the actual unchanged membership when its save fails', async () => {
    api.save.mockRejectedValue(new Error('Synthetic membership failure'));
    api.member.mockResolvedValue(payload(false, { ...record, active: false }));
    const result = await saveAssigneeConfiguration(options);
    expect(result.error.message).toBe('Synthetic membership failure');
    expect(result.member.auto_assignment_enabled).toBe(false);
    expect(result.record.active).toBe(false);
    expect(api.automatic).toHaveBeenCalledExactlyOnceWith('1', '31', false);
  });

  it('enables automatic assignment only after the membership is saved', async () => {
    options.automaticEnabled = true;
    options.originalAutomatic = false;
    api.member.mockImplementation(async () => {
      calls.push('readback');
      return payload(true);
    });
    const result = await saveAssigneeConfiguration(options);
    expect(calls).toEqual(['membership', 'enable', 'readback']);
    expect(result.error).toBeUndefined();
  });

  it('does not enable automatic assignment if the operational save fails', async () => {
    options.automaticEnabled = true;
    options.originalAutomatic = false;
    api.save.mockRejectedValue(new Error('Synthetic membership failure'));
    const result = await saveAssigneeConfiguration(options);
    expect(api.automatic).not.toHaveBeenCalled();
    expect(result.member.auto_assignment_enabled).toBe(false);
  });

  it('returns a partial result with the persisted membership if enabling the native flag fails', async () => {
    options.automaticEnabled = true;
    options.originalAutomatic = false;
    api.automatic.mockRejectedValue(new Error('Synthetic enable failure'));
    const result = await saveAssigneeConfiguration(options);
    expect(result.error.message).toBe('Synthetic enable failure');
    expect(result.record.active).toBe(true);
    expect(result.member.auto_assignment_enabled).toBe(false);
  });

  it('never reports success when readback fails or differs from the requested state', async () => {
    api.member.mockRejectedValueOnce(new Error('Synthetic readback failure'));
    let result = await saveAssigneeConfiguration(options);
    expect(result.readbackError.message).toBe('Synthetic readback failure');
    api.member.mockResolvedValueOnce(payload(true));
    result = await saveAssigneeConfiguration(options);
    expect(result.error).toBeInstanceOf(TypeError);
    expect(result.member.auto_assignment_enabled).toBe(true);
  });

  it('keeps delegated manual configuration independent of the native automatic flag', async () => {
    options.canManageAutomatic = false;
    const result = await saveAssigneeConfiguration(options);
    expect(api.automatic).not.toHaveBeenCalled();
    expect(api.save).toHaveBeenCalledOnce();
    expect(result.record.manual_assignment_enabled).toBe(true);
    expect(result.error).toBeUndefined();
  });

  it('stops after the current account context changes, before another authority is written', async () => {
    let current = true;
    options.isCurrent = () => current;
    api.automatic.mockImplementation(async () => {
      current = false;
    });
    expect(await saveAssigneeConfiguration(options)).toEqual({ stale: true });
    expect(api.save).not.toHaveBeenCalled();
    expect(api.member).not.toHaveBeenCalled();
  });
});
