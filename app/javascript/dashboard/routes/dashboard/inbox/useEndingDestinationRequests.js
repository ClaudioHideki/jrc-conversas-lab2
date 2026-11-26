import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const identifier = value =>
  typeof value === 'string' && /^[1-9]\d{0,18}$/.test(value);
const uuid = value =>
  typeof value === 'string' &&
  /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(value);
const operations = {
  project_task: ['create_task'],
  crm: ['create_lead', 'create_activity'],
  service_desk: ['create_ticket', 'update_ticket'],
};
const validSelection = row =>
  row &&
  identifier(row.origin_id) &&
  identifier(row.readiness_id) &&
  identifier(row.version_id) &&
  typeof row.rule_code === 'string' &&
  row.rule_code.length > 0 &&
  row.rule_code.length <= 100 &&
  typeof row.rule_sha256 === 'string' &&
  /^[0-9a-f]{64}$/.test(row.rule_sha256) &&
  Array.isArray(operations[row.destination_kind]) &&
  operations[row.destination_kind].includes(row.operation);

// Explicit selected writes only. A lost acknowledgement preserves the same
// request UUID; changing account, attendance or effective profile clears data.
export const useEndingDestinationRequests = ({
  accountId,
  qualificationId,
  authorityKey,
  enabled,
  onAccepted,
  onDenied,
}) => {
  const items = ref([]);
  const meta = ref(null);
  const loading = ref(false);
  const selected = ref(null);
  const reviewed = ref(false);
  const busy = ref(false);
  const error = ref('');
  const recorded = ref(false);
  const keys = new Map();
  let generation = 0;
  let readGeneration = 0;
  let disposed = false;
  const identity = () =>
    JSON.stringify([
      String(accountId.value),
      String(qualificationId.value),
      authorityKey.value,
      enabled.value,
    ]);
  const reset = () => {
    generation += 1;
    readGeneration += 1;
    items.value = [];
    meta.value = null;
    loading.value = false;
    selected.value = null;
    reviewed.value = false;
    busy.value = false;
    recorded.value = false;
    error.value = '';
    keys.clear();
  };
  const validPage = (data, page) =>
    data?.contract_version === 1 &&
    data.account_id === String(accountId.value) &&
    data.qualification_id === String(qualificationId.value) &&
    Array.isArray(data.items) &&
    data.items.length <= 20 &&
    data.items.every(validSelection) &&
    data.meta?.page === page &&
    data.meta.per_page === 20 &&
    Number.isSafeInteger(data.meta.total) &&
    data.meta.total >= data.items.length &&
    data.meta.pages === Math.ceil(data.meta.total / 20);
  const load = async (page = 1) => {
    if (!enabled.value || disposed || loading.value || busy.value) return;
    if (!Number.isInteger(page) || page < 1 || page > 1000000) return;
    const scope = identity();
    readGeneration += 1;
    const request = readGeneration;
    const current = () =>
      !disposed && scope === identity() && request === readGeneration;
    loading.value = true;
    items.value = [];
    meta.value = null;
    if (!selected.value) error.value = '';
    try {
      const { data } = await API.manualEndingActions(
        accountId.value,
        qualificationId.value,
        page
      );
      if (!current()) return;
      if (!validPage(data, page)) throw new TypeError('Invalid action preview');
      const ids = data.items.map(row =>
        JSON.stringify([row.origin_id, row.rule_code, row.destination_kind])
      );
      if (new Set(ids).size !== ids.length)
        throw new TypeError('Duplicate action preview');
      items.value = data.items;
      meta.value = data.meta;
    } catch (failure) {
      if (!current()) return;
      error.value = [401, 403, 404].includes(failure.response?.status)
        ? 'DENIED'
        : 'LOAD_FAILED';
      if (error.value === 'DENIED') {
        reset();
        error.value = 'DENIED';
        onDenied();
      }
    } finally {
      if (current()) loading.value = false;
    }
  };
  const open = (row, mode) => {
    if (!enabled.value || disposed || busy.value || selected.value) return;
    if (!validSelection(row)) return;
    if (mode !== 'manual') {
      if (row.ledger !== 'typed' || !identifier(row.attempt_id)) return;
      if (!uuid(row.request_id)) return;
      if (
        mode === 'retry' &&
        (row.can_retry_selected !== true ||
          !['failed', 'blocked'].includes(row.outcome))
      )
        return;
      if (
        mode === 'resume' &&
        (row.can_resume_pending !== true || row.outcome !== 'pending')
      )
        return;
    }
    const token = JSON.stringify([
      mode,
      row.origin_id,
      row.rule_code,
      row.destination_kind,
      row.readiness_id,
      row.version_id,
      row.rule_sha256,
      row.request_id || '',
    ]);
    let key = mode === 'resume' ? row.request_id : keys.get(token);
    if (!key) {
      try {
        key = crypto?.randomUUID?.();
      } catch {
        error.value = 'UNAVAILABLE';
        return;
      }
      if (
        !uuid(key) ||
        key === row.request_id ||
        [...keys.values()].includes(key)
      ) {
        error.value = 'UNAVAILABLE';
        return;
      }
      keys.set(token, key);
    }
    selected.value = { ...row, mode, new_request_id: key };
    reviewed.value = false;
    error.value = '';
    recorded.value = false;
  };
  const cancel = () => {
    if (busy.value) return;
    selected.value = null;
    reviewed.value = false;
  };
  const canSubmit = computed(
    () =>
      enabled.value &&
      selected.value !== null &&
      reviewed.value &&
      !busy.value &&
      !['CHANGED', 'DENIED', 'UNAVAILABLE'].includes(error.value)
  );
  const submit = async () => {
    if (!canSubmit.value) return;
    const row = { ...selected.value };
    const scope = identity();
    const revision = generation;
    const current = () =>
      !disposed && scope === identity() && revision === generation;
    const review = {
      confirmed: true,
      expected_readiness_id: row.readiness_id,
      expected_version_id: row.version_id,
      expected_rule_sha256: row.rule_sha256,
    };
    busy.value = true;
    error.value = '';
    try {
      let response;
      if (row.mode === 'manual') {
        response = await API.requestEndingDestination(
          accountId.value,
          qualificationId.value,
          {
            origin_id: row.origin_id,
            rule_code: row.rule_code,
            destination_kind: row.destination_kind,
            request_key: row.new_request_id,
            review,
          }
        );
      } else {
        review.expected_request_id = row.request_id;
        response =
          row.mode === 'resume'
            ? await API.resumeEndingDestination(
                accountId.value,
                qualificationId.value,
                row.attempt_id,
                review
              )
            : await API.retryEndingDestination(
                accountId.value,
                qualificationId.value,
                row.attempt_id,
                { request_key: row.new_request_id, review }
              );
      }
      if (!current()) return;
      const { data } = response;
      if (
        response.status !== 202 ||
        data?.contract_version !== 1 ||
        data.account_id !== String(accountId.value) ||
        data.qualification_id !== String(qualificationId.value) ||
        data.ledger !== 'typed' ||
        !identifier(data.attempt_id) ||
        data.request_id !== row.new_request_id ||
        data.status !== 'accepted' ||
        data.execution_confirmed !== false ||
        (row.mode === 'resume' && data.attempt_id !== row.attempt_id)
      )
        throw new TypeError('Unverified action intent acknowledgement');
      selected.value = null;
      reviewed.value = false;
      recorded.value = true;
      busy.value = false;
      await onAccepted();
      if (current()) await load(meta.value?.page || 1);
    } catch (failure) {
      if (!current()) return;
      if ([401, 403, 404].includes(failure.response?.status)) {
        reset();
        error.value = 'DENIED';
        onDenied();
      } else {
        error.value = failure.response?.status === 409 ? 'CHANGED' : 'UNKNOWN';
        reviewed.value = false;
      }
    } finally {
      if (current()) busy.value = false;
    }
  };
  watch(
    identity,
    () => {
      reset();
      if (enabled.value) load();
    },
    { immediate: true, flush: 'sync' }
  );
  onBeforeUnmount(() => {
    disposed = true;
    reset();
  });
  return {
    items,
    meta,
    loading,
    selected,
    reviewed,
    busy,
    error,
    recorded,
    canSubmit,
    load,
    openManual: row => open(row, 'manual'),
    openRetry: row => open(row, 'retry'),
    openResume: row => open(row, 'resume'),
    cancel,
    submit,
  };
};
