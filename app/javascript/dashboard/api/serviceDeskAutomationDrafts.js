/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';

const path = account => {
  const id = canonicalId(account);
  if (!id) throw new TypeError('Invalid account');
  return `/api/v1/accounts/${id}/jrc_service_desk`;
};
const verify = (payload, account, unit) => {
  if (
    payload.contract_version !== 1 ||
    payload.account_id !== String(account) ||
    payload.unit_id !== String(unit)
  )
    throw new TypeError('Invalid draft scope');
  return payload;
};
export default {
  async read(account, unit, kind, code) {
    const { data } = await axios.get(`${path(account)}/automation_drafts`, {
      params: { unit_id: unit, kind, code },
      timeout: 30000,
    });
    return verify(data, account, unit).draft;
  },
  async save(account, unit, kind, code, payload, version) {
    const { data } = await axios.put(
      `${path(account)}/automation_drafts`,
      { unit_id: unit, kind, code, payload, expected_version: version },
      { timeout: 30000 }
    );
    return verify(data, account, unit).draft;
  },
  async versions(account, unit, queue) {
    const { data } = await axios.get(`${path(account)}/queue_policy_versions`, {
      params: { unit_id: unit, queue_id: queue },
      timeout: 30000,
    });
    return verify(data, account, unit);
  },
};
