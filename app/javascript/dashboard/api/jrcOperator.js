/* global axios */
export const operatorClient = accountId => {
  const base = `/api/v1/accounts/${Number(accountId)}/operator`;
  if (!Number.isSafeInteger(Number(accountId)) || Number(accountId) < 1)
    throw new Error('Invalid account');
  const get = async (path, params, signal) =>
    (await axios.get(`${base}${path}`, { params, signal })).data;
  const post = async (id, action, data) =>
    (await axios.post(`${base}/bindings/${id}/${action}`, data)).data;
  return {
    context: () => get('/context'),
    bindings: () => get('/bindings'),
    read: (id, action, params, signal) =>
      get(`/bindings/${id}/${action}`, params, signal),
    post,
    pdf: async (id, operation) =>
      (
        await axios.get(`${base}/bindings/${id}/operations/${operation}/pdf`, {
          responseType: 'blob',
        })
      ).data,
  };
};
