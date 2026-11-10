export const LOCAL_ACTIONS = [
  'view',
  'work',
  'team',
  'manage_portfolios',
  'configure',
  'request_transfer',
  'approve_transfer',
  'execute_transfer',
  'request_eligibility',
  'manage_eligibility',
  'export_data',
  'export_history',
  'document_view',
  'document_download',
  'document_upload',
  'document_replace',
  'document_manage',
  'document_restricted',
];
export const INDEPENDENT_GRANTS = LOCAL_ACTIONS.filter(
  value => value.startsWith('document_') || value.startsWith('export_')
);
export const LOCAL_SCOPES = ['authorized', 'own', 'team', 'managed'];
export const LOCAL_ROLES = ['viewer', 'analyst', 'supervisor', 'manager'];
export const ROLE_PRESETS = {
  viewer: { scope: 'authorized', actions: ['view'] },
  analyst: {
    scope: 'own',
    actions: [
      'view',
      'work',
      'request_transfer',
      'document_view',
      'document_upload',
    ],
  },
  supervisor: {
    scope: 'team',
    actions: [
      'view',
      'work',
      'team',
      'request_transfer',
      'approve_transfer',
      'request_eligibility',
      'document_view',
    ],
  },
  manager: { scope: 'managed', actions: [...LOCAL_ACTIONS] },
};
// Mirrors the approved role boundaries in LocalRoleRules; these are ceilings,
// not automatic grants. Existing incompatible choices stay visible for removal.
export const ROLE_ACTION_LIMITS = {
  viewer: [
    'view',
    'export_data',
    'export_history',
    'document_view',
    'document_download',
    'document_restricted',
  ],
  analyst: [
    'view',
    'work',
    'request_transfer',
    'document_view',
    'document_download',
    'document_upload',
    'document_replace',
  ],
  supervisor: [
    'view',
    'work',
    'team',
    'request_transfer',
    'approve_transfer',
    'request_eligibility',
    'export_data',
    'export_history',
    'document_view',
    'document_download',
    'document_restricted',
  ],
  manager: [...LOCAL_ACTIONS],
};
export const editableRoleActions = (role, selected = []) => [
  ...new Set([
    ...(ROLE_ACTION_LIMITS[role] || []),
    ...selected.filter(action => LOCAL_ACTIONS.includes(action)),
  ]),
];
export const editableRoleGrants = (role, selected = []) =>
  editableRoleActions(role, selected).filter(action =>
    INDEPENDENT_GRANTS.includes(action)
  );
export const localRoleDraft = value =>
  value
    ? JSON.parse(JSON.stringify(value))
    : {
        enabled: false,
        roles: JSON.parse(JSON.stringify(ROLE_PRESETS)),
        members: [],
      };
const uniqueAllowed = (values, allowed) =>
  Array.isArray(values) &&
  new Set(values).size === values.length &&
  values.every(value => allowed.includes(value));
export const validateLocalRoleDraft = value => {
  if (value === null) return true;
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value) ||
    Object.keys(value).sort().join() !== 'enabled,members,roles' ||
    typeof value.enabled !== 'boolean' ||
    !value.roles ||
    Object.keys(value.roles).sort().join() !== [...LOCAL_ROLES].sort().join()
  )
    return false;
  if (
    Object.entries(value.roles).some(
      ([name, role]) =>
        !role ||
        Object.keys(role).sort().join() !== 'actions,scope' ||
        !LOCAL_SCOPES.includes(role.scope) ||
        !uniqueAllowed(role.actions, ROLE_ACTION_LIMITS[name])
    )
  )
    return false;
  if (
    !Array.isArray(value.members) ||
    value.members.length > 500 ||
    new Set(value.members.map(member => member?.user_id)).size !==
      value.members.length
  )
    return false;
  return value.members.every(
    member =>
      member &&
      Object.keys(member).sort().join() ===
        'document_categories,grants,role,user_id' &&
      Number.isSafeInteger(member.user_id) &&
      member.user_id > 0 &&
      LOCAL_ROLES.includes(member.role) &&
      uniqueAllowed(member.grants, INDEPENDENT_GRANTS) &&
      Array.isArray(member.document_categories) &&
      member.document_categories.length <= 50 &&
      member.document_categories.every(
        category =>
          typeof category === 'string' && /^[a-zA-Z0-9_-]{1,80}$/.test(category)
      )
  );
};
export const addLocalRoleMember = (value, userID, role) => {
  const draft = localRoleDraft(value);
  if (
    !Number.isSafeInteger(userID) ||
    userID <= 0 ||
    !LOCAL_ROLES.includes(role) ||
    draft.members.some(member => member.user_id === userID)
  )
    throw new Error('INVALID_LOCAL_MEMBER');
  draft.members.push({
    user_id: userID,
    role,
    grants: [],
    document_categories: [],
  });
  if (!validateLocalRoleDraft(draft)) throw new Error('INVALID_LOCAL_ROLES');
  return draft;
};
