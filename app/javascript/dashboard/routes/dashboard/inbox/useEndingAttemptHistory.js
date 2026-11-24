import { onBeforeUnmount, ref, watch } from 'vue';
import ContactCenterAPI from 'dashboard/api/jrcContactCenter';

const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
const timestamp = value =>
  typeof value === 'string' &&
  value.length <= 40 &&
  Number.isFinite(Date.parse(value));
const terminalCodes = {
  succeeded: ['completed'],
  failed: ['destination_failure'],
  blocked: [
    'authorization_denied',
    'reference_unavailable',
    'deactivated',
    'confirmation_required',
    'trigger_pending',
    'operation_unavailable',
  ],
};
const validOutcome = row => {
  if (row.outcome === 'pending')
    return (
      row.result_code === null &&
      row.finished_at === null &&
      row.execution_id === null &&
      row.target === null
    );
  if (!terminalCodes[row.outcome]?.includes(row.result_code)) return false;
  if (!timestamp(row.finished_at)) return false;
  return row.outcome === 'succeeded'
    ? identifier(row.execution_id)
    : row.execution_id === null && row.target === null;
};

const validPage = (body, accountId, qualificationId, page) =>
  body?.contract_version === 1 &&
  body.account_id === String(accountId) &&
  body.qualification_id === String(qualificationId) &&
  (body.call_session_id === null || identifier(body.call_session_id)) &&
  Array.isArray(body.items) &&
  body.items.length <= 20 &&
  body.meta?.page === page &&
  body.meta.per_page === 20 &&
  Number.isSafeInteger(body.meta.total) &&
  body.meta.total >= 0 &&
  body.meta.pages === Math.ceil(body.meta.total / 20) &&
  new Set(body.items.map(row => row.id)).size === body.items.length &&
  body.items.every(
    row =>
      identifier(row.id) &&
      identifier(row.origin_id) &&
      identifier(row.version_id) &&
      typeof row.rule_code === 'string' &&
      row.rule_code.length > 0 &&
      row.rule_code.length <= 100 &&
      row.destination_kind === 'project_task' &&
      timestamp(row.queued_at) &&
      typeof row.request_id === 'string' &&
      /^[0-9a-f-]{36}$/.test(row.request_id) &&
      validOutcome(row) &&
      (row.target === null ||
        (row.target?.kind === 'project_task' &&
          identifier(row.target.id) &&
          identifier(row.target.project_id)))
  );

// Explicit read only. Changing attendance/account/profile clears all receipts
// synchronously; delayed replies never populate another attendance's panel.
export const useEndingAttemptHistory = ({
  accountId,
  qualificationId,
  authorityKey,
}) => {
  const opened = ref(false);
  const items = ref([]);
  const callSessionId = ref(null);
  const meta = ref(null);
  const loading = ref(false);
  const error = ref('');
  let generation = 0;
  let disposed = false;
  const identity = () =>
    JSON.stringify([
      accountId.value,
      qualificationId.value,
      authorityKey.value,
    ]);
  const reset = () => {
    generation += 1;
    opened.value = false;
    items.value = [];
    callSessionId.value = null;
    meta.value = null;
    loading.value = false;
    error.value = '';
  };
  const load = async (page = 1) => {
    if (!opened.value || loading.value || disposed) return;
    const current = ++generation;
    const scope = identity();
    items.value = [];
    callSessionId.value = null;
    meta.value = null;
    error.value = '';
    loading.value = true;
    try {
      const { data } = await ContactCenterAPI.endingAttemptHistory(
        accountId.value,
        qualificationId.value,
        { page }
      );
      if (disposed || current !== generation || scope !== identity()) return;
      if (!validPage(data, accountId.value, qualificationId.value, page))
        throw new TypeError('Invalid native ending attempt page');
      items.value = data.items;
      callSessionId.value = data.call_session_id;
      meta.value = data.meta;
    } catch (failure) {
      if (disposed || current !== generation || scope !== identity()) return;
      error.value = [401, 403, 404].includes(failure.response?.status)
        ? 'DENIED'
        : 'LOAD_FAILED';
    } finally {
      if (!disposed && current === generation && scope === identity())
        loading.value = false;
    }
  };
  const open = () => {
    opened.value = true;
    return load();
  };
  watch(identity, reset, { flush: 'sync' });
  onBeforeUnmount(() => {
    disposed = true;
    reset();
  });
  return {
    opened,
    items,
    callSessionId,
    meta,
    loading,
    error,
    open,
    close: reset,
    load,
  };
};
