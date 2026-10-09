/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';
const id = value => {
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid identifier');
  return result;
};
const base = account =>
  `/api/v1/accounts/${id(account)}/jrc_service_desk/resources`;
const options = signal => ({ signal, timeout: 30000 });

export default {
  list: (account, query, signal) =>
    axios
      .get(base(account), { ...options(signal), params: query })
      .then(result => result.data),
  read: (account, resource, signal) =>
    axios
      .get(`${base(account)}/${id(resource)}`, options(signal))
      .then(result => result.data),
  create: (account, unit, resource, key, signal) =>
    axios
      .post(
        base(account),
        { unit_id: id(unit), resource },
        { ...options(signal), headers: { 'Idempotency-Key': key } }
      )
      .then(result => result.data),
  update: (account, unit, row, resource, signal) =>
    axios
      .patch(
        `${base(account)}/${id(row.id)}`,
        {
          unit_id: id(unit),
          resource,
          expected_lock_version: row.lock_version,
        },
        options(signal)
      )
      .then(result => result.data),
  archive: (account, unit, row, signal) =>
    axios
      .delete(`${base(account)}/${id(row.id)}`, {
        ...options(signal),
        data: { unit_id: id(unit), expected_lock_version: row.lock_version },
      })
      .then(result => result.data),
};
