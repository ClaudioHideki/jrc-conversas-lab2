/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';
const base = account => {
  const id = canonicalId(account);
  if (!id) throw new TypeError('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk/satisfaction_reports`;
};
export default {
  report: (account, params, signal) =>
    axios
      .get(base(account), { params, signal, timeout: 20000 })
      .then(response => response.data),
  export: (account, params, signal) =>
    axios
      .get(`${base(account)}/export`, {
        params,
        signal,
        timeout: 60000,
        responseType: 'blob',
      })
      .then(response => {
        if (!String(response.headers['content-type']).startsWith('text/csv'))
          throw new TypeError('Invalid survey file');
        return response.data;
      }),
};
