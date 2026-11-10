// Transport-independent state for the native paginated calendar. No global store,
// localStorage, business writes, or authorization fallback. Transport is injected.
export const calendarPageQuery = (query, page = 1) => ({
  starts_on: query.startsOn,
  ends_before: query.endsBefore,
  page,
  per_page: 25,
  include_owners: '1',
  ...(query.filters?.search ? { search: query.filters.search } : {}),
  ...(query.filters?.type ? { activity_type: query.filters.type } : {}),
  ...(query.filters?.owner ? { user_id: query.filters.owner } : {}),
  ...(query.filters?.status ? { status: query.filters.status } : {}),
  ...(query.customerSegmentId
    ? { customer_segment_id: query.customerSegmentId }
    : {}),
});

const empty = () => ({
  rows: [],
  owners: [],
  meta: null,
  loading: false,
  error: null,
});
const payload = response => {
  const body = response?.data;
  const meta = body?.meta;
  if (
    !Array.isArray(body?.data) ||
    !meta ||
    !Number.isSafeInteger(meta.total) ||
    meta.total < 0 ||
    !Number.isSafeInteger(meta.page) ||
    !Number.isSafeInteger(meta.pages) ||
    meta.page < 1 ||
    meta.page > meta.pages ||
    meta.per_page !== 25 ||
    meta.pages !== Math.max(1, Math.ceil(meta.total / meta.per_page)) ||
    body.data.length > 25 ||
    body.data.length > meta.total ||
    !body.data.every(
      row => row && Number.isSafeInteger(row.id) && row.id > 0
    ) ||
    new Set(body.data.map(row => row.id)).size !== body.data.length ||
    (body.owners !== undefined &&
      (!Array.isArray(body.owners) ||
        !body.owners.every(
          owner =>
            Number.isSafeInteger(owner.id) &&
            owner.id > 0 &&
            typeof owner.name === 'string'
        )))
  ) {
    throw new Error('INVALID_CALENDAR_PAGE');
  }
  return { rows: body.data, owners: body.owners || [], meta };
};

export const createCalendarPageState = ({
  fetchPage,
  publish,
  currentContext,
}) => {
  let generation = 0;
  let aborter;
  let disposed = false;
  const clear = () => {
    generation += 1;
    aborter?.abort();
    publish(empty());
  };
  const load = async (query, page = 1) => {
    if (disposed) return false;
    const captured = JSON.parse(JSON.stringify(query));
    if (
      !/^[1-9]\d*$/.test(String(captured.accountId)) ||
      !Number.isSafeInteger(Number(captured.accountId)) ||
      !captured.identity ||
      !Number.isSafeInteger(page) ||
      page < 1
    ) {
      clear();
      publish({ ...empty(), error: 'INVALID_CALENDAR_QUERY' });
      return false;
    }
    generation += 1;
    const request = generation;
    aborter?.abort();
    aborter = new AbortController();
    publish({ ...empty(), loading: true });
    const active = () =>
      !disposed &&
      request === generation &&
      currentContext() === captured.identity;
    try {
      const response = await fetchPage(
        captured.accountId,
        calendarPageQuery(captured, page),
        { signal: aborter.signal }
      );
      if (!active()) return false;
      const result = payload(response);
      publish({ ...result, loading: false, error: null });
      return true;
    } catch (error) {
      if (!active()) return false;
      const status = error.response?.status;
      publish({
        ...empty(),
        error: [401, 403, 404].includes(status)
          ? 'ACCESS_DENIED'
          : 'LOAD_FAILED',
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
