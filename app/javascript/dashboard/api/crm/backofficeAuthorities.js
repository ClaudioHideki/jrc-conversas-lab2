/* global axios */
import { backofficeAPI } from './commercialCycle';

const requestUrl = (accountId, requestId) =>
  `${backofficeAPI.urlForAccount(accountId)}/${requestId}`;
const url = (accountId, requestId) =>
  `${requestUrl(accountId, requestId)}/contract_authorities`;
export default {
  list: (accountId, requestId, page, options = {}) =>
    axios.get(url(accountId, requestId), { ...options, params: { page } }),
  create: (accountId, requestId, proposal, options = {}) =>
    axios.post(
      url(accountId, requestId),
      { authority_proposal: proposal },
      options
    ),
  show: (accountId, requestId, proposalId, options = {}) =>
    axios.get(`${url(accountId, requestId)}/${proposalId}`, options),
  pdf: (accountId, requestId, proposalId, options = {}) =>
    axios.get(`${url(accountId, requestId)}/${proposalId}/pdf`, {
      ...options,
      responseType: 'blob',
    }),
  document: (accountId, requestId, proposalId, versionId, options = {}) =>
    axios.get(
      `${url(accountId, requestId)}/${proposalId}/documents/${versionId}`,
      {
        ...options,
        responseType: 'blob',
      }
    ),
  documents: (accountId, requestId, params, options = {}) =>
    axios.get(`${requestUrl(accountId, requestId)}/document_versions`, {
      ...options,
      params,
    }),
};
