/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access.js';
const id = value => {
  const parsed = canonicalId(value);
  if (!parsed) throw new TypeError('Invalid identifier');
  return parsed;
};
export function createCaseClient(transport) {
  const base = account =>
    `/api/v1/accounts/${id(account)}/jrc_service_desk/case_workspaces`;
  const get = (path, params, signal) =>
    transport.get(path, { params, signal, timeout: 20000 }).then(r => r.data);
  const post = (path, data, key, signal) => {
    if (typeof key !== 'string' || !key.trim() || key.length > 120)
      throw new TypeError('Idempotency key required');
    return transport
      .post(path, data, {
        headers: { 'Idempotency-Key': key },
        signal,
        timeout: 30000,
      })
      .then(r => r.data);
  };
  const query = (values, allowed) =>
    Object.fromEntries(
      Object.entries(values)
        .filter(([, v]) => v !== '' && v != null)
        .map(([key, value]) => {
          if (
            !allowed.includes(key) ||
            !['string', 'number'].includes(typeof value)
          )
            throw new TypeError('Invalid filter');
          return [key, key.endsWith('_id') ? id(value) : value];
        })
    );
  return {
    list: (account, values, signal) =>
      get(
        base(account),
        query(values, [
          'kind',
          'unit_id',
          'operator_company_id',
          'page',
          'per_page',
          'status',
          'severity',
          'service_id',
          'category_id',
          'owner_account_user_id',
          'requester_id',
          'source',
          'query',
          'created_from',
          'created_to',
        ]),
        signal
      ),
    show: (account, record, signal) =>
      get(`${base(account)}/${id(record)}`, {}, signal),
    create: (account, unit, record, key, signal) =>
      post(base(account), { unit_id: id(unit), record }, key, signal),
    command: (
      account,
      record,
      action,
      attributes,
      version,
      key,
      signal,
      files = []
    ) => {
      if (!Number.isSafeInteger(version) || version < 0)
        throw new TypeError('Version required');
      let data = { action, attributes, expected_lock_version: version };
      if (files.length) {
        data = new FormData();
        data.append('action', action);
        data.append('attributes', JSON.stringify(attributes));
        data.append('expected_lock_version', String(version));
        files.forEach(file => data.append('files[]', file));
      }
      return post(`${base(account)}/${id(record)}/commands`, data, key, signal);
    },
    related: (account, record, values, signal) =>
      get(
        `${base(account)}/${id(record)}/related`,
        query(values, [
          'type',
          'linked',
          'query',
          'page',
          'per_page',
          'phase',
          'source',
          'requester_id',
          'created_from',
          'created_to',
        ]),
        signal
      ),
    resources: (account, record, values, signal) =>
      get(
        `${base(account)}/${id(record)}/resources`,
        query(values, ['kind', 'linked', 'query', 'page', 'per_page']),
        signal
      ),
    resourceOptions: (account, record, signal, values = {}) =>
      get(
        `${base(account)}/${id(record)}/resource_options`,
        query(values, ['project_query', 'project_page']),
        signal
      ),
    entries: (account, record, values, signal) =>
      get(
        `${base(account)}/${id(record)}/entries`,
        query(values, ['page', 'per_page', 'event_type', 'files_only']),
        signal
      ),
    download: (account, record, entry, file, signal) =>
      transport
        .get(
          `${base(account)}/${id(record)}/entries/${id(entry)}/attachments/${id(file)}`,
          { signal, timeout: 30000, responseType: 'blob' }
        )
        .then(r => r.data),
  };
}
export default createCaseClient({
  get: (...args) => axios.get(...args),
  post: (...args) => axios.post(...args),
});
