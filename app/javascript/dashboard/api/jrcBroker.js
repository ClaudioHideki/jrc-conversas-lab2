/* global axios */

// Account scope is captured per view, never read again from a changed route.
export const createJrcBrokerApi = accountId => {
  if (!Number.isSafeInteger(Number(accountId)) || Number(accountId) < 1) {
    throw new Error('Invalid account');
  }
  const base = `/api/v1/accounts/${Number(accountId)}/jrc_broker`;
  const request = async (method, path, data, key, signal) => {
    const response = await axios({
      method,
      url: `${base}${path}`,
      data,
      signal,
      headers: key ? { 'Idempotency-Key': key } : {},
    });
    return response.data;
  };
  const inboxPath = (id, action) =>
    `/inboxes/${encodeURIComponent(id)}/${action}`;
  return {
    // Use the existing inbox policy with a captured account, not the global cache.
    inboxes: async signal => {
      const response = await axios({
        method: 'get',
        url: `/api/v1/accounts/${Number(accountId)}/inboxes`,
        signal,
      });
      return response.data.payload;
    },
    configuration: signal => request('get', '', undefined, undefined, signal),
    configure: (data, signal) => request('patch', '', data, undefined, signal),
    assignmentPolicy: signal =>
      request('get', '/assignment_policy', undefined, undefined, signal),
    saveAssignmentPolicy: (data, signal) =>
      request('put', '/assignment_policy', data, undefined, signal),
    resources: signal =>
      request('get', '/resources', undefined, undefined, signal),
    adopt: (integrationId, signal) =>
      request('post', '/adopt', { integrationId }, undefined, signal),
    operations: signal =>
      request('get', '/onboarding', undefined, undefined, signal),
    create: (data, key, signal) =>
      request('post', '/onboarding', data, key, signal),
    operation: (id, signal) =>
      request(
        'get',
        `/onboarding/${encodeURIComponent(id)}`,
        undefined,
        undefined,
        signal
      ),
    recover: (id, action, key, signal) =>
      request(
        'post',
        `/onboarding/${encodeURIComponent(id)}/recover`,
        { action },
        key,
        signal
      ),
    status: (id, signal) =>
      request('get', inboxPath(id, 'status'), undefined, undefined, signal),
    pair: (id, key, signal) =>
      request('post', inboxPath(id, 'pair'), {}, key, signal),
    pairOperation: (id, operationId, signal) =>
      request(
        'get',
        `${inboxPath(id, 'pair-operations')}/${encodeURIComponent(operationId)}`,
        undefined,
        undefined,
        signal
      ),
    disconnect: (id, key, signal) =>
      request('post', inboxPath(id, 'disconnect'), {}, key, signal),
    confirmIdentity: (id, observedRevision, key, signal) =>
      request(
        'post',
        inboxPath(id, 'confirm_identity'),
        { observedRevision },
        key,
        signal
      ),
    grants: (id, signal) =>
      request('get', inboxPath(id, 'grants'), undefined, undefined, signal),
    updateGrants: (id, userIds, signal) =>
      request('put', inboxPath(id, 'grants'), { userIds }, undefined, signal),
  };
};
