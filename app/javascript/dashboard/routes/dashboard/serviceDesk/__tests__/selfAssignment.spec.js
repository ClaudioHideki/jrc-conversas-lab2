import { describe, expect, it } from 'vitest';
import { selfAssignment } from '../helpers/selfAssignment';

describe('native self-assignment projection', () => {
  const member = { id: '200', name: 'Synthetic agent' };
  const context = {
    available: true,
    account_id: '1',
    user_id: '50',
    units: [{ id: '10', self_assignee: member }],
  };
  const ticket = {
    account_id: '1',
    unit_id: '10',
    status_phase: 'open',
    permissions: { assign: true },
    assignee: { id: '300' },
  };
  it('uses AccountUser identity and allows taking an already assigned eligible ticket', () => {
    expect(selfAssignment(context, ticket)).toEqual(member);
  });
  it.each([
    { account_id: '2' },
    { unit_id: '11' },
    { permissions: { assign: false } },
    { status_phase: 'closed' },
    { status_phase: 'cancelled' },
    { assignee: member },
  ])(
    'hides assignment when native context denies or no change is needed: %j',
    change => {
      expect(selfAssignment(context, { ...ticket, ...change })).toBeNull();
    }
  );
  it('discards an unavailable context', () => {
    expect(selfAssignment({ ...context, available: false }, ticket)).toBeNull();
  });
});
