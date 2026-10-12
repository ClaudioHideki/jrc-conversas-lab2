/* global axios */
// An explicit account is required for every call, including late responses after account switching.
export const approvalClient = accountId => {
  if (!Number.isSafeInteger(Number(accountId)) || Number(accountId) <= 0)
    throw new Error('INVALID_ACCOUNT');
  const base = `/api/v1/accounts/${Number(accountId)}/approvals`;
  return {
    get: (path, params = {}) => axios.get(`${base}/${path}`, { params }),
    post: (path, body) => axios.post(`${base}/${path}`, body),
    patch: (path, body) => axios.patch(`${base}/${path}`, body),
    revoke: id => axios.delete(`${base}/delegations/${id}`),
  };
};
