import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const digest = value =>
  typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const identity = value =>
  typeof value === 'string' && /^[1-9][0-9]{0,18}$/.test(value);

// An operation receipt proves the historical removal, never the current queue state.
export const useQueueCalendarRemoval = ({
  accountId,
  unitId,
  row,
  contextKey,
  canManage,
  validateCurrent,
  onLock,
  onCurrent,
  onDenied,
}) => {
  const active = ref(false);
  const busy = ref(false);
  const reviewed = ref(false);
  const payload = ref(null);
  const receipt = ref(null);
  const current = ref(null);
  const error = ref('');
  const abandonReviewed = ref(false);
  let generation = 0;
  const canSubmit = computed(
    () =>
      active.value &&
      canManage.value &&
      !busy.value &&
      reviewed.value &&
      !receipt.value &&
      error.value !== 'CONFLICT'
  );
  const clear = () => {
    generation += 1;
    active.value = false;
    busy.value = false;
    reviewed.value = false;
    payload.value = null;
    receipt.value = null;
    current.value = null;
    error.value = '';
    abandonReviewed.value = false;
    onLock(false);
  };
  const denied = problem => {
    if (![401, 403, 404].includes(problem?.response?.status)) return false;
    clear();
    onDenied();
    return true;
  };
  const open = () => {
    if (
      active.value ||
      !canManage.value ||
      !row.value?.binding ||
      !validateCurrent(row.value)
    )
      return;
    clear();
    active.value = true;
    onLock(true);
  };
  const validReceipt = value =>
    value &&
    value.contract_version === 1 &&
    value.format === 'jrc-cc-queue-calendar-removal-v1' &&
    value.account_id === String(accountId.value) &&
    value.unit_id === unitId.value &&
    value.queue_id === payload.value.queue_id &&
    value.idempotency_key === payload.value.idempotency_key &&
    value.removed_binding_id === payload.value.binding_id &&
    value.removed_calendar_digest === row.value.binding.calendar_digest &&
    digest(value.queue_revision_after) &&
    identity(value.audit_id) &&
    value.historical_receipt === true &&
    value.local_only === true &&
    value.pabx_confirmed === false &&
    value.external_impact === 'unknown';
  const fetchCurrent = async sequence => {
    try {
      const { data } = await API.queueCalendar(
        accountId.value,
        unitId.value,
        payload.value.queue_id
      );
      if (sequence !== generation) return;
      if (
        data.account_id !== String(accountId.value) ||
        data.queue_id !== payload.value.queue_id ||
        !validateCurrent(data)
      )
        throw new Error('Unverified current queue after historical removal');
      current.value = data;
      error.value = '';
    } catch (problem) {
      if (sequence === generation && !denied(problem))
        error.value = receipt.value ? 'CURRENT_UNKNOWN' : 'CONFLICT';
    }
  };
  const submit = async () => {
    if (!canSubmit.value) return;
    const sequence = generation;
    if (!payload.value)
      payload.value = Object.freeze({
        unit_id: unitId.value,
        queue_id: row.value.queue_id,
        binding_id: row.value.binding.id,
        expected_revision: row.value.queue_revision,
        idempotency_key: crypto.randomUUID(),
        reviewed: true,
      });
    busy.value = true;
    error.value = '';
    try {
      const { data } = await API.removeQueueCalendar(
        accountId.value,
        payload.value.queue_id,
        payload.value
      );
      if (sequence !== generation) return;
      if (!validReceipt(data))
        throw new Error('Unverified historical queue calendar removal receipt');
      receipt.value = data;
      await fetchCurrent(sequence);
    } catch (problem) {
      if (sequence === generation && !denied(problem)) {
        reviewed.value = false;
        error.value =
          problem?.response?.status === 409 ? 'CONFLICT' : 'UNCERTAIN';
      }
    } finally {
      if (sequence === generation) busy.value = false;
    }
  };
  const refresh = async () => {
    if (!active.value || !canManage.value || !receipt.value || busy.value)
      return;
    const sequence = generation;
    busy.value = true;
    await fetchCurrent(sequence);
    if (sequence === generation) busy.value = false;
  };
  const finish = () => {
    if (busy.value || (payload.value && !current.value)) return;
    const value = current.value;
    clear();
    if (value) onCurrent(value);
  };
  const abandon = () => {
    if (
      active.value &&
      !busy.value &&
      !receipt.value &&
      error.value === 'UNCERTAIN' &&
      abandonReviewed.value
    )
      clear();
  };
  const reloadAfterConflict = async () => {
    if (!active.value || busy.value || error.value !== 'CONFLICT') return;
    const sequence = generation;
    busy.value = true;
    await fetchCurrent(sequence);
    if (sequence !== generation) return;
    busy.value = false;
    if (current.value) finish();
  };
  watch([accountId, unitId, row, contextKey, canManage], clear, {
    flush: 'sync',
  });
  onBeforeUnmount(clear);
  return {
    active,
    busy,
    reviewed,
    payload,
    receipt,
    current,
    error,
    abandonReviewed,
    canSubmit,
    open,
    clear,
    submit,
    refresh,
    finish,
    abandon,
    reloadAfterConflict,
  };
};
