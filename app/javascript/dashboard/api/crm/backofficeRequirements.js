/* global axios */
import ApiClient from '../ApiClient';
const rules = new ApiClient('crm/backoffice_requirement_rules', {
  accountScoped: true,
});
const requests = new ApiClient('crm/backoffice_requests', {
  accountScoped: true,
});
const requestURL = (accountId, requestId) =>
  `${requests.urlForAccount(accountId)}/${requestId}/requirements`;
export const backofficeRequirementsAPI = {
  capabilities: (accountId, options = {}) =>
    axios.get(`${rules.urlForAccount(accountId)}/capabilities`, options),
  scopeOptions: (accountId, params, options = {}) =>
    axios.get(`${rules.urlForAccount(accountId)}/options`, {
      ...options,
      params,
    }),
  listRules: (accountId, options = {}) =>
    axios.get(rules.urlForAccount(accountId), options),
  saveRule: (accountId, key, payload) =>
    key
      ? axios.patch(
          `${rules.urlForAccount(accountId)}/${encodeURIComponent(key)}`,
          payload
        )
      : axios.post(rules.urlForAccount(accountId), payload),
  show: (accountId, requestId, options = {}) =>
    axios.get(requestURL(accountId, requestId), options),
  history: (accountId, requestId, params, options = {}) =>
    axios.get(`${requestURL(accountId, requestId)}/history`, {
      ...options,
      params,
    }),
  adopt: (accountId, requestId, payload) =>
    axios.post(`${requestURL(accountId, requestId)}/adopt`, payload),
  answer: (accountId, requestId, payload) =>
    axios.post(`${requestURL(accountId, requestId)}/answer`, payload),
};
