// Presentation only: only server-authorized transitions may be offered.
export function closureOptions(data) {
  if (!data?.policy || !Array.isArray(data.options)) return [];
  return data.options.filter(row => ['close', 'resolve'].includes(row.action));
}
export function preferredClosure(options) {
  const close = options.filter(row => row.action === 'close');
  if (close.length === 1) return close[0].key;
  if (close.length > 1) return '';
  const resolve = options.filter(row => row.action === 'resolve');
  return resolve.length === 1 ? resolve[0].key : '';
}
export function closureFieldsValid(rule, draft, canSeeNotes) {
  if (!rule || !['close', 'resolve'].includes(rule.action)) return false;
  const requirements = rule.requirements || {};
  if (
    !canSeeNotes &&
    (requirements.note ||
      requirements.solution ||
      requirements.evidence ||
      Object.keys(requirements.fields || {}).length)
  )
    return false;
  if (requirements.note && !draft.note?.trim()) return false;
  if (requirements.solution && !draft.solution?.trim()) return false;
  if (
    requirements.evidence &&
    !/^[1-9]\d*(\s*,\s*[1-9]\d*)*$/.test(draft.evidence?.trim() || '')
  )
    return false;
  return Object.entries(requirements.fields || {}).every(([key, spec]) => {
    const value = draft.fields?.[key];
    const absent =
      value === undefined ||
      value === null ||
      (typeof value === 'string' && !value.trim());
    if (absent) return !spec.required && !Object.hasOwn(spec, 'equals');
    if (
      spec.type === 'integer' &&
      (!/^-?\d+$/.test(String(value)) || !Number.isSafeInteger(Number(value)))
    )
      return false;
    if (spec.type === 'boolean' && typeof value !== 'boolean') return false;
    if (spec.type === 'text' && typeof value !== 'string') return false;
    const typed = spec.type === 'integer' ? Number(value) : value;
    return !Object.hasOwn(spec, 'equals') || typed === spec.equals;
  });
}
