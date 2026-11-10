const presenceFields = new Set([
  'active_at',
  'availability',
  'availability_status',
  'auto_offline',
]);

// Preserve every access field, including future scopes. Native presence
// refreshes alone do not change the authorization context of a form.
export const accountMembershipAccess = membership =>
  membership
    ? Object.fromEntries(
        Object.entries(membership).filter(([key]) => !presenceFields.has(key))
      )
    : null;
