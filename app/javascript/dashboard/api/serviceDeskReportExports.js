/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';
const id = value => {
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid identifier');
  return result;
};
const result = response => response.data;
const clientFor = (resource, extraTypes = []) => {
  const base = account =>
    `/api/v1/accounts/${id(account)}/jrc_service_desk/${resource}`;
  return {
    create: (account, values, signal) =>
      axios
        .post(base(account), values, { signal, timeout: 20000 })
        .then(result),
    list: (account, unit, signal) =>
      axios
        .get(base(account), {
          signal,
          timeout: 20000,
          params: { unit_id: id(unit) },
        })
        .then(result),
    download: (account, exportId, signal) =>
      axios
        .get(`${base(account)}/${id(exportId)}/download`, {
          signal,
          timeout: 60000,
          responseType: 'blob',
        })
        .then(response => {
          const mime = String(response.headers['content-type']);
          if (
            ![
              'text/csv',
              'application/pdf',
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              ...extraTypes,
            ].some(value => mime.startsWith(value))
          )
            throw new TypeError('Invalid export content');
          return response.data;
        }),
  };
};

export const managerialReportExports = clientFor('managerial_report_exports', [
  'text/html',
]);
export default clientFor('report_exports');
