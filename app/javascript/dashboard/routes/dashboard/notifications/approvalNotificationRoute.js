// Only native actor types and the current account can open an approval notification.
export const approvalNotificationRoute = (notification, accountId) => {
  if (notification.notification_type !== 'approval_event') return null;
  const account = Number(accountId);
  if (
    !Number.isSafeInteger(account) ||
    account <= 0 ||
    Number(notification.account_id) !== account ||
    Number(notification.primary_actor?.account_id) !== account
  )
    return null;
  if (notification.primary_actor_type === 'JrcApprovals::AuditEvent') {
    const screen = notification.meta?.approval_target;
    if (!['own-delegations', 'inbox'].includes(screen)) return null;
    return { name: 'jrc_approvals', params: { accountId: account, screen } };
  }
  const id = Number(notification.primary_actor_id);
  if (
    notification.primary_actor_type !== 'JrcApprovals::Request' ||
    !Number.isSafeInteger(id) ||
    id <= 0 ||
    Number(notification.primary_actor?.id) !== id
  )
    return null;
  return {
    name: 'jrc_approvals',
    params: { accountId: account, screen: 'inbox', id },
  };
};
