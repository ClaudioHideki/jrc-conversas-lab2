// Source state for the approved addendum. No current state fallback for TRR.
export const RETENTION_STATUSES = [
  'onboarding',
  'active',
  'at_risk',
  'churned',
  'inactive',
];
export const normalizeRetentionPolicy = input => {
  if (input === null) return null;
  if (
    !input ||
    typeof input !== 'object' ||
    Array.isArray(input) ||
    Object.keys(input).some(
      key =>
        !['eligible_statuses', 'contact_mode', 'target_percent'].includes(key)
    )
  )
    throw new Error('INVALID_RETENTION_POLICY');
  const statuses = input.eligible_statuses;
  if (
    !Array.isArray(statuses) ||
    !statuses.length ||
    new Set(statuses).size !== statuses.length ||
    statuses.some(value => !RETENTION_STATUSES.includes(value))
  )
    throw new Error('INVALID_RETENTION_STATUSES');
  if (
    !['relationship_status', 'registered_contact'].includes(input.contact_mode)
  )
    throw new Error('INVALID_CONTACT_MODE');
  const target = input.target_percent;
  if (
    target !== null &&
    target !== undefined &&
    (typeof target !== 'number' ||
      !Number.isFinite(target) ||
      target < 0 ||
      target > 100)
  )
    throw new Error('INVALID_RETENTION_TARGET');
  return {
    eligible_statuses: [...statuses].sort(),
    contact_mode: input.contact_mode,
    target_percent: target ?? null,
  };
};
export const normalizeRetentionResult = data => {
  if (
    !data ||
    data.metric !== 'TRR' ||
    typeof data.available !== 'boolean' ||
    typeof data.from !== 'string' ||
    typeof data.to !== 'string'
  )
    throw new Error('UNCONFIRMED_RETENTION');
  if (data.available) {
    if (
      ![data.initial, data.retained, data.exits].every(Number.isSafeInteger) ||
      data.initial <= 0 ||
      data.retained < 0 ||
      data.exits < 0 ||
      data.initial !== data.retained + data.exits ||
      typeof data.value !== 'number' ||
      !Number.isFinite(data.value) ||
      data.value < 0 ||
      data.value > 100 ||
      Math.abs(
        data.value - Math.round((data.retained * 10000) / data.initial) / 100
      ) > 0.00001
    )
      throw new Error('UNCONFIRMED_RETENTION');
  } else if (data.value !== null) throw new Error('UNCONFIRMED_RETENTION');
  return data;
};
export const createRetentionState = ({ identity, read, publish }) => {
  let epoch = 0;
  let controller;
  let disposed = false;
  let state = { data: null, busy: false, error: '' };
  const emit = patch => {
    state = { ...state, ...patch };
    publish({ ...state });
  };
  const clear = () => {
    epoch += 1;
    controller?.abort();
    emit({ data: null, busy: false, error: '' });
  };
  return {
    clear,
    dispose: () => {
      disposed = true;
      clear();
    },
    async load(accountId, params) {
      if (disposed) return false;
      clear();
      const token = epoch;
      const actor = identity();
      controller = new AbortController();
      emit({ busy: true });
      try {
        const result = await read(
          accountId,
          JSON.parse(JSON.stringify(params)),
          { signal: controller.signal }
        );
        if (disposed || token !== epoch || actor !== identity()) return false;
        emit({ data: normalizeRetentionResult(result.data), error: '' });
        return true;
      } catch (error) {
        if (token === epoch && actor === identity() && !disposed)
          emit({
            data: null,
            error: [401, 403, 404].includes(error.response?.status)
              ? 'DENIED'
              : 'UNAVAILABLE',
          });
        return false;
      } finally {
        if (token === epoch && actor === identity() && !disposed)
          emit({ busy: false });
      }
    },
  };
};
