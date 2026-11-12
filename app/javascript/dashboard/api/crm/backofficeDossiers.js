/* global axios */
import { backofficeAPI } from './commercialCycle';

const url = (accountId, requestId) =>
  `${backofficeAPI.urlForAccount(accountId)}/${requestId}/completion_dossiers`;
export default {
  list: (accountId, requestId, page, options = {}) =>
    axios.get(url(accountId, requestId), { ...options, params: { page } }),
  seal: (accountId, requestId, digest, options = {}) =>
    axios.post(
      url(accountId, requestId),
      { completion_dossier: { expected_manifest_digest: digest } },
      options
    ),
  download: (accountId, requestId, id, options = {}) =>
    axios.get(`${url(accountId, requestId)}/${id}/download`, {
      ...options,
      responseType: 'blob',
    }),
};
