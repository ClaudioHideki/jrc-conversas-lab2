import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const validReceipt = (item, code) =>
  item?.rule_code === code &&
  item?.prospective_only === true &&
  typeof item?.id === 'string' &&
  /^[1-9][0-9]*$/.test(item.id) &&
  typeof item?.version_id === 'string' &&
  /^[1-9][0-9]*$/.test(item.version_id) &&
  Number.isFinite(Date.parse(item?.activated_at));

export const useEndingRuleActivation = ({
  accountId,
  rule,
  revision,
  disabled,
  onDenied,
  onBusy,
}) => {
  const reviewed = ref(false);
  const busy = ref(false);
  const receipt = ref(null);
  const previousReceipt = ref(null);
  const loading = ref(false);
  const loaded = ref(false);
  const error = ref('');
  const stale = ref(false);
  const identity = computed(() =>
    JSON.stringify([String(accountId.value), revision.value, rule.value])
  );
  let generation = 0;
  let requestKey = '';
  let alive = true;
  const reset = () => {
    generation += 1;
    requestKey = '';
    reviewed.value = false;
    busy.value = false;
    receipt.value = null;
    previousReceipt.value = null;
    loading.value = false;
    loaded.value = false;
    error.value = '';
    stale.value = false;
    onBusy(false);
  };
  const canSubmit = computed(
    () =>
      !disabled.value &&
      !busy.value &&
      !loading.value &&
      loaded.value &&
      !receipt.value &&
      !stale.value &&
      reviewed.value &&
      rule.value?.active === true &&
      (rule.value?.execution_mode === 'automatic' ||
        (rule.value?.destination_schema_version === 2 &&
          rule.value?.execution_mode === 'agent_confirmation')) &&
      /^[a-f0-9]{64}$/.test(revision.value)
  );
  const load = async () => {
    if (busy.value || loading.value) return;
    const version = generation;
    const submitted = identity.value;
    const account = String(accountId.value);
    const code = rule.value.code;
    const expectedRevision = revision.value;
    const current = () =>
      alive && generation === version && identity.value === submitted;
    loading.value = true;
    error.value = '';
    onBusy(true);
    try {
      const response = await API.endingRuleReadiness(
        account,
        code,
        expectedRevision
      );
      if (!current()) return;
      const data = response.data;
      if (
        String(data.account_id) !== account ||
        data.reviewed_revision !== expectedRevision ||
        !['last_review', 'applicable_review'].every(
          key => data[key] === null || validReceipt(data[key], code)
        )
      )
        throw new Error('Unverified ending readiness response');
      previousReceipt.value = data.last_review;
      receipt.value = data.applicable_review;
      loaded.value = true;
    } catch (failure) {
      if (!current()) return;
      if ([401, 403, 404].includes(failure?.response?.status)) {
        reset();
        onDenied();
      } else if (failure?.response?.status === 409) {
        stale.value = true;
        error.value = 'STALE';
      } else error.value = 'LOAD_FAILED';
    } finally {
      if (current()) {
        loading.value = false;
        onBusy(false);
      }
    }
  };
  watch(
    identity,
    () => {
      reset();
      load();
    },
    { immediate: true, flush: 'sync' }
  );
  const submit = async () => {
    if (!canSubmit.value) return;
    const version = generation;
    const submitted = identity.value;
    const account = String(accountId.value);
    const code = rule.value.code;
    const expectedRevision = revision.value;
    const current = () =>
      alive && generation === version && identity.value === submitted;
    requestKey ||= crypto.randomUUID();
    busy.value = true;
    error.value = '';
    onBusy(true);
    try {
      const response = await API.activateEndingRule(
        account,
        code,
        expectedRevision,
        requestKey
      );
      if (!current()) return;
      const data = response.data;
      const item = data.item;
      if (
        String(data.account_id) !== account ||
        data.reviewed_revision !== expectedRevision ||
        !validReceipt(item, code)
      )
        throw new Error('Unverified ending activation acknowledgement');
      receipt.value = item;
    } catch (failure) {
      if (!current()) return;
      if ([401, 403, 404].includes(failure?.response?.status)) {
        reset();
        onDenied();
      } else if (failure?.response?.status === 409) {
        stale.value = true;
        reviewed.value = false;
        error.value = 'STALE';
      } else {
        // A lost acknowledgement is uncertain. Keep this exact key and context
        // for an explicit user retry; never generate a second automatic POST.
        error.value = 'FAILED';
      }
    } finally {
      if (current()) {
        busy.value = false;
        onBusy(false);
      }
    }
  };
  onBeforeUnmount(() => {
    alive = false;
    reset();
  });
  return {
    reviewed,
    busy,
    receipt,
    previousReceipt,
    loading,
    loaded,
    error,
    stale,
    canSubmit,
    submit,
    load,
  };
};
