// Scope-bound transport state; no business permission is inferred in the browser.
export const createRequirementState = ({
  currentIdentity,
  fetch,
  mutate,
  publish,
}) => {
  let generation = 0;
  let data = null;
  let busy = false;
  let disposed = false;
  let aborter;
  let conflicted = false;
  const notify = (error = '') => publish({ data, busy, error, conflicted });
  const clear = () => {
    generation += 1;
    aborter?.abort();
    data = null;
    busy = false;
    conflicted = false;
    notify();
  };
  const valid = body =>
    body &&
    Number.isSafeInteger(body.plan_revision) &&
    body.plan_revision >= 0 &&
    Array.isArray(body.items) &&
    body.items.every(
      item =>
        typeof item.key === 'string' &&
        item.definition &&
        typeof item.status === 'string' &&
        typeof item.blocking === 'boolean' &&
        Number.isSafeInteger(item.response_revision) &&
        item.response_revision >= 0
    );
  const load = async context => {
    if (disposed) return false;
    clear();
    const token = generation;
    const snapshot = { ...context };
    const identity = currentIdentity();
    aborter = new AbortController();
    busy = true;
    notify();
    try {
      const response = await fetch(snapshot, { signal: aborter.signal });
      if (disposed || token !== generation || identity !== currentIdentity())
        return false;
      if (!valid(response.data))
        throw new Error('INVALID_REQUIREMENT_RESPONSE');
      data = response.data;
      return true;
    } catch (failure) {
      if (disposed || token !== generation || identity !== currentIdentity())
        return false;
      busy = false;
      notify(
        [401, 403, 404].includes(failure.response?.status)
          ? 'DENIED'
          : 'LOAD_ERROR'
      );
      return false;
    } finally {
      if (!disposed && token === generation && identity === currentIdentity()) {
        busy = false;
        if (data) notify();
      }
    }
  };
  const execute = async (context, operation, payload) => {
    if (disposed || busy || !data || conflicted) return false;
    const snapshot = { ...context };
    const input = JSON.parse(JSON.stringify(payload));
    const token = generation;
    const identity = currentIdentity();
    busy = true;
    notify();
    try {
      const response = await mutate(snapshot, operation, input);
      if (disposed || token !== generation || identity !== currentIdentity())
        return false;
      if (!valid(response.data))
        throw new Error('INVALID_REQUIREMENT_RESPONSE');
      data = response.data;
      busy = false;
      notify();
      return true;
    } catch (failure) {
      if (disposed || token !== generation || identity !== currentIdentity())
        return false;
      const status = failure.response?.status;
      if ([401, 403, 404].includes(status)) data = null;
      conflicted = status === 409 || !status || status >= 500;
      busy = false;
      let message = status === 409 ? 'CONFLICT' : 'SAVE_ERROR';
      if ([401, 403, 404].includes(status)) message = 'DENIED';
      notify(message);
      return false;
    }
  };
  return {
    load,
    execute,
    clear,
    dispose: () => {
      disposed = true;
      clear();
    },
  };
};

export const requirementAnswerPayload = (item, value, decision, note = '') => {
  const definition = item.definition;
  const kind =
    definition.kind === 'conditional'
      ? definition.requirement_kind
      : definition.kind;
  if (kind === 'information') {
    let answer = value;
    if (definition.answer_type === 'number') {
      if (value === '' || value === null || typeof value === 'boolean')
        throw new Error('INVALID_VALUE');
      answer = Number(value);
      if (!Number.isFinite(answer)) throw new Error('INVALID_VALUE');
    }
    if (definition.answer_type === 'boolean') {
      if (!['true', 'false', true, false].includes(value))
        throw new Error('INVALID_VALUE');
      answer = value === 'true' || value === true;
    }
    return { value: answer };
  }
  if (['consultation', 'confirmation', 'human_activity'].includes(kind)) {
    const choices =
      kind === 'confirmation'
        ? ['confirmed', 'rejected']
        : ['completed', 'rejected'];
    if (
      !choices.includes(decision) ||
      typeof note !== 'string' ||
      !note.trim() ||
      note.trim().length > 4000
    )
      throw new Error('INVALID_VALUE');
    return { decision, note: note.trim() };
  }
  if (
    kind === 'validation' &&
    definition.source === 'manual_review' &&
    ['approved', 'rejected'].includes(decision)
  ) {
    return { decision };
  }
  throw new Error('NATIVE_VERIFICATION_REQUIRED');
};
