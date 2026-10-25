/* global axios */
import { canonicalId } from '../routes/dashboard/serviceDesk/helpers/access';

export function createAutomationInsightsClient(http) {
  return {
    async retryAlert(account, unit, row, reason) {
      const accountId = canonicalId(account);
      const unitId = canonicalId(unit);
      if (!accountId || !unitId || !canonicalId(row.id) || !reason?.trim())
        throw new TypeError('Invalid retry scope');
      const response = await http.post(
        `/api/v1/accounts/${accountId}/jrc_service_desk/automation_insights/clock_alerts/retry`,
        {
          unit_id: unitId,
          alert_id: row.id,
          expected_attempts: row.attempts,
          reason: reason.trim(),
        }
      );
      if (
        response.data.account_id !== accountId ||
        response.data.unit_id !== unitId ||
        response.data.applied !== true
      )
        throw new TypeError('Unverified alert retry');
      return response.data;
    },
    async read(account, unit, kind, params, signal) {
      params ||= {};
      const accountId = canonicalId(account);
      const unitId = canonicalId(unit);
      if (
        !accountId ||
        !unitId ||
        !['ola', 'notifications', 'clock_alerts'].includes(kind)
      )
        throw new TypeError('Invalid insights scope');
      const response = await http.get(
        `/api/v1/accounts/${accountId}/jrc_service_desk/automation_insights/${kind}`,
        {
          params: { ...params, unit_id: unitId },
          signal,
          timeout: 30000,
        }
      );
      const payload = response.data;
      if (
        payload.contract_version !== 1 ||
        payload.account_id !== accountId ||
        payload.unit_id !== unitId
      )
        throw new TypeError('Foreign insights response');
      if (
        kind === 'ola' &&
        params.queue_id &&
        payload.queue_id !== canonicalId(params.queue_id)
      )
        throw new TypeError('Foreign queue insight');
      if (
        kind === 'ola' &&
        (!Number.isSafeInteger(payload.total) ||
          payload.total < 0 ||
          !Array.isArray(payload.items))
      )
        throw new TypeError('Invalid clock metrics');
      if (
        kind === 'notifications' &&
        payload.delivery_rate != null &&
        (!Number.isFinite(payload.delivery_rate) ||
          payload.delivery_rate < 0 ||
          payload.delivery_rate > 100)
      )
        throw new TypeError('Invalid delivery metric');
      return payload;
    },
  };
}
export default createAutomationInsightsClient({
  get: (...args) => axios.get(...args),
  post: (...args) => axios.post(...args),
});
