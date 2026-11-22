const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
const digest = value =>
  typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
const ownScope = (unit, group) =>
  unit?.scope?.issuer_company_id === group.issuer_company_id &&
  unit?.scope?.business_unit_id === group.business_unit_id;

// This only rejects incoherent presentation. The server reauthorizes the complete impact before every effect.
export const verifiedPauseApprovalPreview = (data, context, values) => {
  const preview = data?.preview;
  const payload = preview?.payload;
  const coverage = payload?.coverage;
  const units = coverage?.units;
  const groups = coverage?.groups;
  if (
    String(data?.account_id) !== context.account ||
    String(data?.account_user_id) !== context.member ||
    preview?.required !== true ||
    preview?.local_only !== true ||
    preview?.provider_confirmed !== false ||
    !digest(preview?.digest) ||
    payload?.version !== 1 ||
    payload?.request_id !== values.command_id ||
    coverage?.account_id !== context.account ||
    coverage?.actor_account_user_id !== context.member ||
    !identifier(coverage?.actor_user_id) ||
    coverage?.all_affected_units !== true ||
    coverage?.local_only !== true ||
    coverage?.provider_confirmed !== false ||
    !digest(coverage?.digest) ||
    !Array.isArray(units) ||
    !units.length ||
    !Array.isArray(groups) ||
    !groups.length
  )
    return null;
  const intent = payload.intent;
  if (
    intent?.reason_code !== values.reason_code?.trim() ||
    intent?.queue_id !== (values.queue_id || null) ||
    intent?.justification !== (values.justification?.trim() || '')
  )
    return null;
  const identities = units.map(unit => unit?.id);
  if (
    identities.some(id => !identifier(id)) ||
    new Set(identities).size !== identities.length ||
    units.some(unit => typeof unit?.name !== 'string' || !unit.name.trim())
  )
    return null;
  const scopes = groups.map(group => {
    if (
      !identifier(group?.issuer_company_id) ||
      !(
        group?.business_unit_id === null || identifier(group?.business_unit_id)
      ) ||
      !Array.isArray(group?.unit_ids) ||
      !group.unit_ids.length ||
      group.unit_ids.some(id => !identifier(id))
    )
      return null;
    const members = group.unit_ids.map(id =>
      units.find(unit => unit.id === id && ownScope(unit, group))
    );
    if (members.some(unit => !unit)) return null;
    return {
      company: group.issuer_company_id,
      business: group.business_unit_id,
      units: members.map(unit => ({ id: unit.id, name: unit.name })),
    };
  });
  if (scopes.some(scope => !scope)) return null;
  const scopedIds = scopes.flatMap(scope => scope.units.map(unit => unit.id));
  if (
    new Set(scopedIds).size !== scopedIds.length ||
    scopedIds.length !== identities.length ||
    identities.some(id => !scopedIds.includes(id))
  )
    return null;
  return { digest: preview.digest, scopes };
};
