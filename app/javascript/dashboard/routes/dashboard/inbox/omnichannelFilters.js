export const ASSIGNEE_FILTERS = Object.freeze({
  ME: 'me',
  MINE_OR_SHARED: 'mine_or_shared',
  UNASSIGNED: 'unassigned',
  ALL: 'all',
});

export const matchesAssigneeFilter = (
  conversation,
  filter,
  currentUserId,
  sharedInboxIds = [],
  personalInboxView = false
) => {
  const { assignee, assignee_type: assigneeType } = conversation.meta || {};
  if (
    filter === ASSIGNEE_FILTERS.MINE_OR_SHARED ||
    (filter === ASSIGNEE_FILTERS.ME && personalInboxView)
  ) {
    return (
      matchesAssigneeFilter(conversation, ASSIGNEE_FILTERS.ME, currentUserId) ||
      (assigneeType !== 'AgentBot' &&
        sharedInboxIds.some(id => Number(id) === Number(conversation.inbox_id)))
    );
  }
  if (filter === ASSIGNEE_FILTERS.ME) {
    return Boolean(
      (assignee &&
        assigneeType !== 'AgentBot' &&
        Number(assignee.id) === Number(currentUserId)) ||
        conversation.meta?.participant_ids?.some(
          id => Number(id) === Number(currentUserId)
        )
    );
  }
  if (filter === ASSIGNEE_FILTERS.UNASSIGNED)
    return !assignee || assigneeType === 'AgentBot';
  return filter === ASSIGNEE_FILTERS.ALL;
};

export const canManageAssigneeFilters = ({
  role,
  customRoleId,
  permissions = [],
}) =>
  (role === 'administrator' && customRoleId === null) ||
  permissions.some(permission =>
    [
      'conversation_manage',
      'jrc_contact_center_supervise',
      'jrc_contact_center_configure',
    ].includes(permission)
  );

export const assigneeFilterOptions = (
  canManageAssignments,
  canShare = false
) => [
  ...(canShare
    ? [
        {
          key: ASSIGNEE_FILTERS.MINE_OR_SHARED,
          labelKey: 'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.MINE_OR_SHARED',
          icon: 'i-lucide-users-round',
        },
      ]
    : []),
  {
    key: ASSIGNEE_FILTERS.ME,
    labelKey: 'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ME',
    icon: 'i-lucide-user-round-check',
  },
  ...(canManageAssignments
    ? [
        {
          key: ASSIGNEE_FILTERS.UNASSIGNED,
          labelKey: 'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.UNASSIGNED',
          icon: 'i-lucide-user-round-x',
        },
        {
          key: ASSIGNEE_FILTERS.ALL,
          labelKey: 'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ALL',
          icon: 'i-lucide-users-round',
        },
      ]
    : []),
];

export const resolveAssigneeFilter = (
  value,
  canManageAssignments,
  canShare = false
) => {
  const options = assigneeFilterOptions(canManageAssignments, canShare);
  if (!value && canShare && !canManageAssignments)
    return ASSIGNEE_FILTERS.MINE_OR_SHARED;
  return options.some(option => option.key === value)
    ? value
    : ASSIGNEE_FILTERS.ME;
};
