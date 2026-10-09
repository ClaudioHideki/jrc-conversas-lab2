/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access.js';
import { normalizeQuery } from '../routes/dashboard/serviceDesk/helpers/query.js';
const id = value => {
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid identifier');
  return result;
};
const base = account => `/api/v1/accounts/${id(account)}/jrc_service_desk`;
export default {
  board: (account, kind, query, signal) => {
    if (!['tasks', 'approvals', 'incidents', 'problems'].includes(kind))
      throw new TypeError('Unknown board');
    const {
      status,
      query: search,
      owner_account_user_id: owner,
      ...paging
    } = query;
    const values = normalizeQuery(paging);
    if (status !== undefined) {
      if (typeof status !== 'string' || !/^[a-z_]{1,40}$/.test(status))
        throw new TypeError('Invalid status');
      values.status = status;
    }
    if (search !== undefined) {
      if (typeof search !== 'string' || search.length > 200)
        throw new TypeError('Invalid search');
      values.query = search;
    }
    if (owner !== undefined) values.owner_account_user_id = id(owner);
    if (
      Object.keys(values).some(
        key =>
          ![
            'unit_id',
            'operator_company_id',
            'page',
            'per_page',
            'status',
            'query',
            'owner_account_user_id',
          ].includes(key)
      )
    )
      throw new TypeError('Invalid board filter');
    return axios
      .get(`${base(account)}/board`, {
        params: { ...values, kind },
        signal,
        timeout: 20000,
      })
      .then(response => response.data);
  },
  incident: (account, incidentId, signal) =>
    axios
      .get(`${base(account)}/incidents/${id(incidentId)}`, {
        signal,
        timeout: 20000,
      })
      .then(response => response.data),
  createIncident: (account, unitId, incident, key, signal) =>
    axios
      .post(
        `${base(account)}/incidents`,
        { unit_id: id(unitId), incident },
        { headers: { 'Idempotency-Key': key }, signal, timeout: 20000 }
      )
      .then(response => response.data),
  updateIncident: (account, unitId, row, incident, signal) =>
    axios
      .patch(
        `${base(account)}/incidents/${id(row.id)}`,
        {
          unit_id: id(unitId),
          incident,
          expected_lock_version: row.lock_version,
        },
        { signal, timeout: 20000 }
      )
      .then(response => response.data),
  report: (account, query, signal) =>
    axios
      .get(`${base(account)}/reports`, {
        params: normalizeQuery(query),
        signal,
        timeout: 20000,
      })
      .then(response => response.data),
};
