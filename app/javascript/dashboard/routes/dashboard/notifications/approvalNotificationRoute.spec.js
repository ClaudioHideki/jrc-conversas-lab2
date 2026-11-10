import { describe, expect, it } from 'vitest';
import { approvalNotificationRoute } from './approvalNotificationRoute';

const notification = {
  notification_type: 'approval_event',
  account_id: 1,
  primary_actor_type: 'JrcApprovals::Request',
  primary_actor_id: 23,
  primary_actor: { id: 23, account_id: 1, meta: {} },
};
describe('approval notification native navigation', () => {
  it('opens the exact request in the current account', () => {
    expect(approvalNotificationRoute(notification, 1)).toEqual({
      name: 'jrc_approvals',
      params: { accountId: 1, screen: 'inbox', id: 23 },
    });
  });
  it.each(['own-delegations', 'inbox'])(
    'opens the bounded delegation destination %s',
    screen => {
      expect(
        approvalNotificationRoute(
          {
            ...notification,
            primary_actor_type: 'JrcApprovals::AuditEvent',
            meta: { approval_target: screen },
          },
          1
        )
      ).toEqual({ name: 'jrc_approvals', params: { accountId: 1, screen } });
    }
  );
  it.each([
    { ...notification, account_id: 9 },
    { ...notification, primary_actor: { id: 23, account_id: 9 } },
    { ...notification, primary_actor_id: '23/injected' },
    { ...notification, primary_actor: { id: 24, account_id: 1 } },
    { ...notification, primary_actor_type: 'User' },
    {
      ...notification,
      primary_actor_type: 'JrcApprovals::AuditEvent',
      meta: { approval_target: 'https://unsafe.invalid' },
    },
  ])('refuses foreign or malformed notification navigation', value => {
    expect(approvalNotificationRoute(value, 1)).toBeNull();
  });
  it('leaves conversation notification routing to its existing native flow', () => {
    expect(
      approvalNotificationRoute(
        { ...notification, notification_type: 'conversation_mention' },
        1
      )
    ).toBeNull();
  });
});
