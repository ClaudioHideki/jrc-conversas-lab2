// Reads are bound to account/request/checklist/key and never reuse a denied result.
export const createRequirementHistoryState = ({ read, identity, publish }) => {
  let generation = 0;
  let controller;
  let disposed = false;
  const clear = () => {
    generation += 1;
    controller?.abort();
    publish({ data: null, busy: false, error: '' });
  };
  const load = async (accountId, requestId, params) => {
    clear();
    if (disposed) return false;
    const token = generation;
    const context = identity();
    const captured = { ...params };
    controller = new AbortController();
    const signal = controller.signal;
    const valid = () =>
      !disposed &&
      token === generation &&
      context === identity() &&
      !signal.aborted;
    publish({ data: null, busy: true, error: '' });
    try {
      const { data } = await read(accountId, requestId, captured, { signal });
      if (!valid()) return false;
      if (
        String(data?.request_id) !== String(requestId) ||
        data.key !== captured.key ||
        data.plan_revision !== captured.plan_revision ||
        !Array.isArray(data.data) ||
        !data.meta
      )
        throw Error('Invalid historical scope');
      publish({ data, busy: false, error: '' });
      return true;
    } catch {
      if (valid())
        publish({ data: null, busy: false, error: 'HISTORY_UNAVAILABLE' });
      return false;
    }
  };
  return {
    clear,
    load,
    dispose: () => {
      disposed = true;
      clear();
    },
  };
};

export const requirementRecordedValue = (answer, copy) => {
  if (!answer || typeof answer !== 'object') return '';
  if (typeof answer.decision === 'string')
    return copy(answer.decision === 'approved' ? 'APPROVE' : 'REJECT');
  if (typeof answer.value === 'boolean')
    return copy(answer.value ? 'YES' : 'NO');
  if (typeof answer.value === 'string' || Number.isFinite(answer.value))
    return String(answer.value);
  return '';
};
