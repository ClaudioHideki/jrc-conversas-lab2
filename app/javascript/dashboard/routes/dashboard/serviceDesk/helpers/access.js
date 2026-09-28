export function canonicalId(value) {
  if (typeof value === 'number' && !Number.isSafeInteger(value))
    return null;
  if (!['number', 'string'].includes(typeof value))
    return null;
  const text = String(value);
  if (!/^[1-9]\d{0,18}$/.test(text))
    return null;
  return BigInt(text) <= 9223372036854775807n ? text : null;
}
// Navigation visibility is not authorization. Only the server grants operations.
export function hasServiceDeskFeature(store, accountId) {
  const id = canonicalId(accountId);
  const getter = store.getters['accounts/isFeatureEnabledonAccount'];
  return !!id && BigInt(id) <= BigInt(Number.MAX_SAFE_INTEGER) && typeof getter === 'function' && getter(Number(id), 'jrc_service_desk') === true;
}
export function createServiceDeskGuard(store, refreshAccount) {
  return async to => {
    const id = canonicalId(to.params.accountId);
    if (!id || typeof refreshAccount !== 'function')
      return false;
    try {
      // The native accounts/get action swallows transport errors and uses the
      // current browser path. Explicit target verification avoids stale flags
      // and the previous Account during an account-to-account navigation.
      const account = await refreshAccount(id);
      if (canonicalId(account?.id) !== id || typeof account?.features !== 'object')
        return false;
      if (account.features.jrc_service_desk !== true) {
        return { name: 'home', params: { accountId: id } };
      }
      return hasServiceDeskFeature(store, id);
    }
    catch {
      return false;
    }
  };
}
export function canRead(context, resource) {
  return context?.available === true && context?.capabilities?.[resource]?.index === true;
}
export function canAct(record, action) {
  return record?.permissions?.[action] === true;
}
// A structural preview contains no records. Once a backend context exists,
// even visual navigation respects its explicit capabilities (never a role).
export function canPreviewScreen(context, definition) {
  if (!definition)
    return false;
  if (!context)
    return true;
  if (context.available !== true)
    return false;
  if (definition.key === 'overview')
    return true;
  if (definition.key === 'new')
    return context.units.some(unit => unit.permissions.create_ticket === true);
  if (definition.key === 'settings')
    return canRead(context, 'settings');
  return canRead(context, definition.resource || definition.key);
}
