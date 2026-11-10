// Native routes only. This link grants no source access; the destination API reauthorizes the record.
const routes = new Map([
  ['JrcCrm::Deal', ['crm_deals', 'dealId']],
  [
    'JrcCrm::BackofficeRequest',
    ['crm_backoffice_request', 'requestId', 'parameter'],
  ],
  ['JrcCrm::Proposal', ['crm_proposals', 'proposalId']],
  ['JrcCrm::SalesOrder', ['crm_orders', 'orderId']],
  ['JrcCrm::Contract', ['crm_contracts', 'contractId']],
]);
const id = value => {
  if (!['number', 'string'].includes(typeof value)) return null;
  const text = String(value);
  return /^[1-9]\d*$/.test(text) && Number.isSafeInteger(Number(text))
    ? text
    : null;
};
export const approvalOriginRoute = (accountId, request) => {
  const account = id(accountId);
  const resource = id(request?.resource_id);
  const route = routes.get(request?.resource_type);
  if (!account || !resource || !route) return null;
  if (request.account_id !== undefined && id(request.account_id) !== account)
    return null;
  const destination = { name: route[0], params: { accountId: account } };
  if (route[2] === 'parameter') destination.params[route[1]] = resource;
  else destination.query = { [route[1]]: resource };
  return destination;
};
