/* global axios */
export const createJrcMigrationsApi = accountId => {
  if (!Number.isSafeInteger(Number(accountId)) || Number(accountId) < 1) {
    throw new Error('Invalid account');
  }
  const base = `/api/v1/accounts/${Number(accountId)}/jrc_migration_batches`;
  const request = async (method, path, data, signal) => {
    const response = await axios({
      method,
      url: `${base}${path}`,
      data,
      signal,
    });
    return response.data;
  };
  return {
    list: (signal, before) =>
      request(
        'get',
        before ? `?before=${encodeURIComponent(before)}` : '',
        undefined,
        signal
      ),
    show: (id, signal) => request('get', `/${id}`, undefined, signal),
    create: (data, signal) => request('post', '', data, signal),
    preview: (id, signal) => request('post', `/${id}/preview`, {}, signal),
    execute: (id, signal) => request('post', `/${id}/execute`, {}, signal),
    scanMedia: (id, itemId, signal) =>
      request('post', `/${id}/items/${itemId}/scan`, {}, signal),
    recoverMedia: (id, itemId, signal) =>
      request('post', `/${id}/items/${itemId}/recover_media`, {}, signal),
    reconciliation: (id, signal) =>
      request('get', `/${id}/reconciliation`, undefined, signal),
    accept: (id, note, signal) =>
      request('post', `/${id}/accept`, { note }, signal),
    errors: (id, signal) => request('get', `/${id}/errors`, undefined, signal),
    events: (id, before, signal) =>
      request(
        'get',
        `/${id}/events?before=${encodeURIComponent(before)}`,
        undefined,
        signal
      ),
  };
};
