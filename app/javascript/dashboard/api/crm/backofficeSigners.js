/* global axios */
import { backofficeAPI } from './commercialCycle';

const url = (accountId, requestId) =>
  `${backofficeAPI.urlForAccount(accountId)}/${requestId}/contract_signers`;

export default {
  list: (accountId, requestId, page, options = {}) =>
    axios.get(url(accountId, requestId), { ...options, params: { page } }),
  contacts: (accountId, requestId, params, options = {}) =>
    axios.get(`${url(accountId, requestId)}/contacts`, { ...options, params }),
  create: (accountId, requestId, signerRoster, options = {}) =>
    axios.post(
      url(accountId, requestId),
      { signer_roster: signerRoster },
      options
    ),
};
