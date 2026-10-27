export const ASSIGNEE_FILTERS = Object.freeze({
  ME: 'me',
  UNASSIGNED: 'unassigned',
  ALL: 'all',
});

export const matchesAssigneeFilter = (conversation, filter, currentUserId) => {
  const { assignee, assignee_type: assigneeType } = conversation.meta || {};
  if (filter === ASSIGNEE_FILTERS.ME) {
    return Boolean(
      assignee &&
        assigneeType !== 'AgentBot' &&
        Number(assignee.id) === Number(currentUserId)
    );
  }
  if (filter === ASSIGNEE_FILTERS.UNASSIGNED) return !assignee;
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

export const assigneeFilterOptions = canManageAssignments => [
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

export const resolveAssigneeFilter = (value, canManageAssignments) => {
  const options = assigneeFilterOptions(canManageAssignments);
  return options.some(option => option.key === value)
    ? value
    : ASSIGNEE_FILTERS.ME;
};
