// The detail is a separate authorized read; summaries never carry raw historic values.
export const createPortfolioHistoryDetailState = ({
  read,
  identity,
  notify = () => {},
}) => {
  let generation = 0;
  let abort;
  let disposed = false;
  let state = { data: null, busy: false, error: '' };
  const publish = next => {
    state = next;
    notify(state);
  };
  const clear = () => {
    generation += 1;
    abort?.abort();
    publish({ data: null, busy: false, error: '' });
  };
  const load = async (accountId, groupId, eventId) => {
    clear();
    if (disposed) return false;
    const current = generation;
    const scope = identity();
    abort = new AbortController();
    const signal = abort.signal;
    const live = () =>
      !disposed &&
      current === generation &&
      scope === identity() &&
      !signal.aborted;
    publish({ data: null, busy: true, error: '' });
    try {
      const { data } = await read(accountId, groupId, eventId, { signal });
      if (!live()) return false;
      if (
        data?.projection !== 'scoped_historical_detail' ||
        String(data.group_id) !== String(groupId) ||
        String(data.event_id) !== String(eventId) ||
        typeof data.available !== 'boolean'
      )
        throw new Error('Invalid historical response');
      if (
        data.available &&
        (!data.before ||
          !data.after ||
          !data.references ||
          typeof data.digest !== 'string')
      )
        throw new Error('Incomplete history');
      publish({ data, busy: false, error: '' });
      return true;
    } catch (failure) {
      if (live())
        publish({
          data: null,
          busy: false,
          error: [401, 403, 404].includes(failure.response?.status)
            ? 'DENIED'
            : 'FAILED',
        });
      return false;
    }
  };
  return {
    load,
    clear,
    dispose: () => {
      disposed = true;
      clear();
    },
  };
};

// Format only authorized server data as text. Never evaluate HTML or origin URLs.
export const portfolioHistoricalValue = (field, value, references, text) => {
  if (value === null || value === undefined) return text('EMPTY');
  if (field === 'rules' && typeof value === 'object')
    return Object.entries(value)
      .map(
        ([key, item]) =>
          `${text(`FIELDS.${key}`)}: ${portfolioHistoricalValue(key, item, references, text)}`
      )
      .join('\n');
  const registry = {
    owner_id: 'users',
    team_id: 'teams',
    business_unit_id: 'units',
    segment_id: 'segments',
  }[field];
  if (registry)
    return references?.[registry]?.[String(value)] || text('UNAVAILABLE');
  if (field === 'customers' && Array.isArray(value))
    return (
      value
        .map(
          row =>
            `${text('ASSIGNMENT')} ${row[0]}: ${text(row[1] ? 'ACTIVE' : 'INACTIVE')}`
        )
        .join('\n') || text('EMPTY')
    );
  if (field === 'goals' && Array.isArray(value))
    return (
      value
        .map(row =>
          [
            row.metric,
            ...['baseline', 'target', 'current']
              .filter(key => row[key] !== undefined)
              .map(key => `${text(`GOALS.${key}`)}: ${row[key]}`),
            row.unit,
          ]
            .filter(item => item !== undefined && item !== '')
            .join(' | ')
        )
        .join('\n') || text('EMPTY')
    );
  if (field === 'portfolio_capacity_limits' && Array.isArray(value))
    return (
      value
        .map(
          row =>
            `${references?.users?.[String(row.user_id)] || text('UNAVAILABLE')}: ${row.maximum} ${text(`UNITS.${row.unit || 'customers'}`)}; ${text('AVAILABILITY')}: ${row.availability}; ${text('DEDICATION')}: ${row.dedication}`
        )
        .join('\n') || text('EMPTY')
    );
  if (typeof value === 'boolean') return text(value ? 'YES' : 'NO');
  if (['visibility', 'status'].includes(field)) return text(`VALUES.${value}`);
  if (typeof value === 'string' || typeof value === 'number')
    return String(value);
  return text('UNAVAILABLE');
};
