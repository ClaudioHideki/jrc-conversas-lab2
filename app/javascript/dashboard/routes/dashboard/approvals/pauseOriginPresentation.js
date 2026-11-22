export const validPauseOrigin = request => {
  const origin = request?.origin;
  if (
    request?.resource_type !== 'JrcContactCenter::PauseApprovalScope' ||
    request?.module_key !== 'contact_center' ||
    request?.event_key !== 'pause' ||
    origin?.kind !== 'contact_center_pause' ||
    origin?.scope_id !== String(request.resource_id) ||
    origin?.historical !== true ||
    origin?.own_scope_only !== true ||
    origin?.local_only !== true ||
    origin?.provider_confirmed !== false ||
    !/^[0-9a-f]{64}$/.test(origin?.context_digest || '') ||
    !/^[0-9a-f]{64}$/.test(origin?.justification_digest || '') ||
    typeof origin?.reason_label !== 'string' ||
    !origin.reason_label.trim() ||
    !Array.isArray(origin?.scope_unit_ids) ||
    !Array.isArray(origin?.scope_unit_names) ||
    !origin.scope_unit_ids.length ||
    origin.scope_unit_ids.length !== origin.scope_unit_names.length ||
    origin.unit_count !== origin.scope_unit_ids.length
  )
    return false;
  return (
    origin.scope_unit_ids.every(
      id => typeof id === 'string' && /^[1-9]\d{0,18}$/.test(id)
    ) &&
    new Set(origin.scope_unit_ids).size === origin.scope_unit_ids.length &&
    origin.scope_unit_names.every(
      name => typeof name === 'string' && name.trim().length > 0
    )
  );
};
