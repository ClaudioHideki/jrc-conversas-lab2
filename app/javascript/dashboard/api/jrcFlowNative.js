/* global axios */
export const createJrcFlowNativeApi = accountId => {
  const account = Number(accountId);
  if (!Number.isSafeInteger(account) || account < 1)
    throw new Error('Invalid account');
  const base = `/api/v1/accounts/${account}/jrc_flow_delegation`;
  const request = async (method, path, data, signal) =>
    (await axios({ method, url: base + path, data, signal })).data;
  return {
    configuration: signal =>
      request('get', '/configuration', undefined, signal),
    configure: (brokerOrigin, nativeCredential, signal) =>
      request(
        'put',
        '/configuration',
        { brokerOrigin, nativeCredential },
        signal
      ),
    register: (challengeId, transferNonce, inboxIds, signal) =>
      request(
        'post',
        '/registration',
        { challengeId, transferNonce, inboxIds },
        signal
      ),
    revoke: (id, signal) =>
      request('delete', `/registration/${encodeURIComponent(id)}`, {}, signal),
    session: (inboxIds, scopes, signal) =>
      request('post', '/sessions', { inboxIds, scopes }, signal),
    close: (id, signal) =>
      request('delete', `/sessions/${encodeURIComponent(id)}`, {}, signal),
    editorContext: (id, signal) =>
      request(
        'get',
        `/sessions/${encodeURIComponent(id)}/editor-context`,
        undefined,
        signal
      ),
    claimInstallation: (grantId, transferNonce, signal) =>
      request('post', '/installations', { grantId, transferNonce }, signal),
    revokeInstallation: (id, signal) =>
      request('delete', `/installations/${encodeURIComponent(id)}`, {}, signal),
    editorRequest: async (
      method,
      path,
      body,
      signal,
      idempotencyKey,
      mediaHeaders
    ) => {
      if (!path.startsWith(base + '/sessions/'))
        throw new Error('Invalid Flow path');
      const headers = {
        ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
        ...(mediaHeaders
          ? { 'Content-Type': 'application/octet-stream', ...mediaHeaders }
          : {}),
      };
      return (await axios({ method, url: path, data: body, signal, headers }))
        .data;
    },
    inboxes: async signal =>
      (
        await axios({
          method: 'get',
          url: `/api/v1/accounts/${account}/inboxes`,
          signal,
        })
      ).data.payload,
  };
};
