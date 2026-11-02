/* global axios */
import { backofficeAPI } from './commercialCycle';

const url = (accountId, requestId) =>
  `${backofficeAPI.urlForAccount(accountId)}/${requestId}/contract_signatures`;
export default {
  list: (accountId, requestId, page, options = {}) =>
    axios.get(url(accountId, requestId), { ...options, params: { page } }),
  show: (accountId, requestId, deliveryId, page, options = {}) =>
    axios.get(`${url(accountId, requestId)}/${deliveryId}`, {
      ...options,
      params: { page },
    }),
};
