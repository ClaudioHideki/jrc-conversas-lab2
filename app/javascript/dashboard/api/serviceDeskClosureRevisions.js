/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';
export function createClosureRevisionClient(http) {
  const request = async (
    account,
    action,
    values,
    { signal, key, method = 'get' } = {}
  ) => {
    const id = canonicalId(account);
    if (!id || !canonicalId(values.unit_id))
      throw new TypeError('Explicit Account and unit required');
    const url = `/api/v1/accounts/${id}/jrc_service_desk/closure_revisions${action ? `/${action}` : ''}`;
    const options = {
      signal,
      timeout: 30000,
      ...(key ? { headers: { 'Idempotency-Key': key } } : {}),
    };
    const response =
      method === 'get'
        ? await http.get(url, { ...options, params: values })
        : await http.post(url, values, options);
    if (
      response.data?.contract_version !== 1 ||
      canonicalId(response.data.account_id) !== id
    )
      throw new TypeError('Foreign closure revision response');
    return response.data;
  };
  return { request };
}
export default createClosureRevisionClient({
  get: (...args) => axios.get(...args),
  post: (...args) => axios.post(...args),
});
