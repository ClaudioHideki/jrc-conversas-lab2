/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';
const id = value => {
  const result = canonicalId(value);
  if (!result) throw new TypeError('Invalid scope');
  return result;
};
const root = account =>
  `/api/v1/accounts/${id(account)}/jrc_service_desk/automation_publications`;
const verify = (data, account, unit) => {
  if (
    data.contract_version !== 1 ||
    data.account_id !== String(account) ||
    data.unit_id !== String(unit)
  )
    throw new TypeError('Invalid publication scope');
  return data;
};
export default {
  async options(account, unit, kind, signal, serviceId = null) {
    const { data } = await axios.get(`${root(account)}/options`, {
      params: {
        unit_id: id(unit),
        kind,
        ...(serviceId ? { service_id: id(serviceId) } : {}),
      },
      signal,
      timeout: 30000,
    });
    return verify(data, account, unit);
  },
  async list(account, unit, kind, signal, filters = {}) {
    const { data } = await axios.get(root(account), {
      params: { unit_id: id(unit), kind, ...filters },
      signal,
      timeout: 30000,
    });
    return verify(data, account, unit);
  },
  async read(account, unit, publicationId, signal) {
    const { data } = await axios.get(`${root(account)}/${id(publicationId)}`, {
      signal,
      timeout: 30000,
    });
    return verify(data, account, unit).publication;
  },
  async preview(account, unit, attributes, facts, at, signal) {
    const { data } = await axios.post(
      `${root(account)}/preview`,
      { unit_id: id(unit), attributes, facts, ...(at ? { at } : {}) },
      { signal, timeout: 30000 }
    );
    return verify(data, account, unit).preview;
  },
  async publish(account, unit, command, signal) {
    const { data } = await axios.post(
      root(account),
      { unit_id: id(unit), ...command },
      { signal, timeout: 30000 }
    );
    return verify(data, account, unit);
  },
};
