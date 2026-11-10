export const ADJUSTABLE_TYPES = {
  discount_cents: 'integer',
  payment_condition: 'choice',
  payment_method: 'choice',
  installments_count: 'integer',
  first_billing_days: 'integer',
  first_due_date: 'date',
};
export const financialChangeSet = (values, draft, fields) => {
  const result = {};
  Object.entries(fields || {}).forEach(([key, rule]) => {
    const type = ADJUSTABLE_TYPES[key];
    if (!type) throw new Error('UNKNOWN_FIELD');
    let value = draft[key];
    if (type === 'integer') {
      if (!['string', 'number'].includes(typeof value) || value === '')
        throw new Error('INVALID_NUMBER');
      if (typeof value === 'string' && !/^\d+$/.test(value))
        throw new Error('INVALID_NUMBER');
      value = Number(value);
      if (!Number.isSafeInteger(value) || value < rule.min || value > rule.max)
        throw new Error('OUTSIDE_POLICY');
    }
    if (type === 'choice' && !rule.options?.includes(value))
      throw new Error('OUTSIDE_POLICY');
    if (
      type === 'date' &&
      (typeof value !== 'string' ||
        !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
        new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) !== value)
    )
      throw new Error('INVALID_DATE');
    if (value !== values[key]) result[key] = value;
  });
  return result;
};
export const normalizeAdjustmentRules = (fields, enabled, allowed) => {
  if (!enabled) return null;
  if (
    !fields ||
    !Object.keys(fields).length ||
    Object.keys(fields).some(key => !allowed.includes(key))
  )
    throw new Error('CONFIGURE_FIELDS');
  const result = {};
  Object.entries(fields).forEach(([key, value]) => {
    const kind = ADJUSTABLE_TYPES[key];
    if (!kind) throw new Error('CONFIGURE_FIELDS');
    if (kind === 'choice') {
      const options = Array.isArray(value.options)
        ? value.options
        : String(value.options || '')
            .split(',')
            .map(v => v.trim())
            .filter(Boolean);
      if (
        !options.length ||
        options.length > 50 ||
        new Set(options).size !== options.length ||
        options.some(v => !/^[a-zA-Z0-9_-]{1,80}$/.test(v))
      )
        throw new Error('CONFIGURE_OPTIONS');
      result[key] = { options };
    } else {
      const keys =
        kind === 'integer' ? ['min', 'max'] : ['min_days', 'max_days'];
      const [min, max] = keys.map(name => value[name]);
      let maximum = kind === 'date' ? 36600 : 2147483647;
      if (key === 'discount_cents') maximum = Number.MAX_SAFE_INTEGER;
      if (
        ![min, max].every(v => Number.isSafeInteger(v) && v >= 0) ||
        min > max ||
        max > maximum ||
        (key === 'installments_count' && min < 1)
      )
        throw new Error('CONFIGURE_LIMITS');
      result[key] = { [keys[0]]: min, [keys[1]]: max };
    }
  });
  return { schema_version: 1, fields: result };
};
