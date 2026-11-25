import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const resultCodes = {
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

// One explicit pending operation, never the qualification-wide dispatcher.
// Its immutable attempt identity makes an uncertain acknowledgement safe to
// review again; no automatic POST or local fabricated outcome is permitted.
export const usePendingEndingRun = ({
  accountId,
  qualificationId,
  authorityKey,
  enabled,
  onComplete,
  onDenied,
}) => {
  const selected = ref(null);
  const reviewed = ref(false);
  const busy = ref(false);
  const error = ref('');
  let generation = 0;
  let alive = true;
  const identity = () =>
    JSON.stringify([
      String(accountId.value),
      String(qualificationId.value),
      authorityKey.value,
    ]);
  const reset = () => {
    generation += 1;
    selected.value = null;
    reviewed.value = false;
    busy.value = false;
    error.value = '';
  };
  const open = row => {
    if (
      !enabled.value ||
      busy.value ||
      row.outcome !== 'pending' ||
      row.can_reprocess_pending !== true
    )
      return;
    error.value = '';
    reviewed.value = false;
    selected.value = {
      id: row.id,
      version_id: row.version_id,
      request_id: row.request_id,
      rule_code: row.rule_code,
    };
  };
  const cancel = () => {
    if (!busy.value) reset();
  };
  const canSubmit = computed(
    () =>
      enabled.value && selected.value !== null && reviewed.value && !busy.value
  );
  const submit = async () => {
    if (!canSubmit.value) return;
    const currentGeneration = generation;
    const scope = identity();
    const row = { ...selected.value };
    const account = String(accountId.value);
    const qualification = String(qualificationId.value);
    const current = () =>
      alive &&
      currentGeneration === generation &&
      scope === identity() &&
      enabled.value;
    busy.value = true;
    error.value = '';
    try {
      const { data } = await API.runPendingEndingAttempt(
        account,
        qualification,
        row.id,
        {
          confirmed: true,
          expected_request_key: row.request_id,
          expected_version_id: row.version_id,
        }
      );
      if (!current()) return;
      if (
        data.account_id !== account ||
        data.qualification_id !== qualification ||
        data.attempt_id !== row.id ||
        !resultCodes[data.outcome]?.includes(data.result_code)
      ) {
        throw new TypeError('Unverified pending operation result');
      }
      selected.value = null;
      reviewed.value = false;
      if (data.outcome !== 'succeeded') error.value = 'NATIVE_REFUSAL';
      await onComplete();
    } catch (failure) {
      if (!current()) return;
      const status = failure?.response?.status;
      if ([401, 403, 404].includes(status)) {
        onDenied();
        reset();
        error.value = 'DENIED';
      } else if (status === 409) {
        selected.value = null;
        reviewed.value = false;
        error.value = 'CHANGED';
        await onComplete();
      } else {
        reviewed.value = false;
        error.value = 'UNKNOWN';
      }
    } finally {
      if (current()) busy.value = false;
    }
  };
  watch([identity, () => enabled.value], reset, { flush: 'sync' });
  onBeforeUnmount(() => {
    alive = false;
    reset();
  });
  return { selected, reviewed, busy, error, canSubmit, open, cancel, submit };
};
