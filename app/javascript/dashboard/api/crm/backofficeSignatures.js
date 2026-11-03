/* global axios */
import { backofficeAPI } from './commercialCycle';

const url = (accountId, requestId) =>
  `${backofficeAPI.urlForAccount(accountId)}/${requestId}/contract_signatures`;
export default {
  preparation: (accountId, requestId, options = {}) =>
    axios.get(`${url(accountId, requestId)}/preparation`, options),
  create: (accountId, requestId, attributes, options = {}) =>
    axios.post(
      url(accountId, requestId),
      { signature_delivery: attributes },
      options
    ),
  cancelPrepared: (accountId, requestId, deliveryId, options = {}) =>
    axios.post(
      `${url(accountId, requestId)}/${deliveryId}/cancel_prepared`,
      {},
      options
    ),
  list: (accountId, requestId, page, options = {}) =>
    axios.get(url(accountId, requestId), { ...options, params: { page } }),
  show: (accountId, requestId, deliveryId, page, options = {}) =>
    axios.get(`${url(accountId, requestId)}/${deliveryId}`, {
      ...options,
      params: { page },
    }),
};
