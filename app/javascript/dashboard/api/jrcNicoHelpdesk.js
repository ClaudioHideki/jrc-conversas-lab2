/* global axios */

const base = accountId =>
  `/api/v1/accounts/${Number(accountId)}/jrc_nico/helpdesk`;

export default {
  show: accountId => axios.get(base(accountId)),
  events: accountId => axios.get(`${base(accountId)}/events`),
  approvals: accountId => axios.get(`${base(accountId)}/approvals`),
  createPolicy: (accountId, definition) =>
    axios.post(`${base(accountId)}/policies`, { definition }),
  publishPolicy: (accountId, policy) =>
    axios.post(`${base(accountId)}/policies/${policy.id}/publish`, {
      digest: policy.digest,
    }),
  disablePolicy: (accountId, policyId, reason, requestKey) =>
    axios.post(`${base(accountId)}/policies/${policyId}/disable`, {
      reason,
      request_key: requestKey,
    }),
  simulate: (accountId, input) =>
    axios.post(`${base(accountId)}/simulate`, input),
  prepare: (accountId, input) =>
    axios.post(`${base(accountId)}/approvals`, input),
  approve: (accountId, approval) =>
    axios.post(`${base(accountId)}/approvals/${approval.id}/approve`, {
      payload_digest: approval.payload_digest,
    }),
  cancel: (accountId, approval) =>
    axios.post(`${base(accountId)}/approvals/${approval.id}/cancel`),
  report: (accountId, policyId, filters = {}) =>
    axios.get(`${base(accountId)}/report`, {
      params: {
        policy_id: policyId,
        ...(Object.keys(filters).length ? { filters } : {}),
      },
    }),
  reports: (accountId, policyId, page = 1) =>
    axios.get(`${base(accountId)}/reports`, {
      params: { policy_id: policyId, page },
    }),
  reportHistory: (accountId, reportId) =>
    axios.get(`${base(accountId)}/reports/${Number(reportId)}`),
  groupPreview: (accountId, input) =>
    axios.post(`${base(accountId)}/group_preview`, input),
  groupPrepare: (accountId, input) =>
    axios.post(`${base(accountId)}/group_prepare`, input),
  kpis: (accountId, policyId, from, options = {}) =>
    axios.get(`${base(accountId)}/kpis`, {
      params: { policy_id: policyId, from, ...options },
    }),
};
