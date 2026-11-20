import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';

export const validEndingReason = row =>
  ['code', 'name', 'category'].every(
    key =>
      typeof row[key] === 'string' &&
      row[key].trim() &&
      row[key] === row[key].trim() &&
      row[key].length <= (key === 'code' ? 100 : 120)
  ) &&
  typeof row.description === 'string' &&
  row.description.length <= 2000 &&
  Number.isInteger(row.order) &&
  row.order >= 0 &&
  row.order <= 1000 &&
  typeof row.active === 'boolean';
const copy = value => JSON.parse(JSON.stringify(value));

export const useEndingReasonCatalog = ({ accountId }) => {
  const entries = ref([]);
  const baseline = ref([]);
  const version = ref(0);
  const policy = ref(null);
  const loading = ref(false);
  const saving = ref(false);
  const error = ref('');
  const saved = ref(false);
  const revision = useConfigurationRevision({
    accountId,
    resource: computed(() => 'acw_policy'),
    draft: entries,
  });
  let generation = 0;
  let alive = true;
  const dirty = computed(
    () => JSON.stringify(entries.value) !== JSON.stringify(baseline.value)
  );
  const valid = computed(
    () =>
      entries.value.length <= 100 &&
      new TextEncoder().encode(JSON.stringify(entries.value)).byteLength <=
        131072 &&
      entries.value.every(validEndingReason) &&
      new Set(entries.value.map(row => row.code)).size === entries.value.length
  );
  const canSave = computed(
    () =>
      policy.value &&
      dirty.value &&
      valid.value &&
      !loading.value &&
      !saving.value &&
      revision.canSave.value
  );
  const current = (request, account) =>
    alive && request === generation && account === String(accountId.value);
  const accept = item => {
    if (
      String(item?.id) !== String(accountId.value) ||
      !item?.voice_reason_catalog ||
      !Number.isInteger(item.voice_reason_catalog.version) ||
      item.voice_reason_catalog.version < 0 ||
      !Array.isArray(item.voice_reason_catalog.entries) ||
      item.voice_reason_catalog.entries.length > 100 ||
      !item.voice_reason_catalog.entries.every(validEndingReason)
    )
      throw new Error('Missing authorized ending reason catalog');
    policy.value = item;
    entries.value = copy(item.voice_reason_catalog.entries);
    baseline.value = copy(entries.value);
    version.value = item.voice_reason_catalog.version;
    revision.capture(item);
  };
  const load = async () => {
    if (saving.value || dirty.value) return;
    generation += 1;
    const request = generation;
    const account = String(accountId.value);
    entries.value = [];
    baseline.value = [];
    policy.value = null;
    error.value = '';
    saved.value = false;
    loading.value = true;
    try {
      const response = await API.acwPolicy(account);
      if (current(request, account)) accept(response.data.item);
    } catch {
      if (current(request, account)) error.value = 'LOAD_FAILED';
    } finally {
      if (current(request, account)) loading.value = false;
    }
  };
  const save = async () => {
    if (!canSave.value) return;
    const request = generation;
    const account = String(accountId.value);
    const submitted = copy(entries.value);
    saving.value = true;
    error.value = '';
    saved.value = false;
    try {
      const latest = revision.state.latest || policy.value;
      const response = await API.updateAcwPolicy(account, latest.limits, {
        ...revision.options(),
        voice_reason_catalog: submitted,
      });
      if (!current(request, account)) return;
      accept(response.data.item);
      saved.value = true;
    } catch (failure) {
      if (current(request, account)) {
        if ([401, 403, 404].includes(failure?.response?.status)) {
          entries.value = [];
          baseline.value = [];
          policy.value = null;
          revision.capture(null);
          error.value = 'DENIED';
        } else if (!revision.handleError(failure)) {
          error.value = 'SAVE_FAILED';
          if (!failure.response || failure.response.status >= 500)
            revision.handleError({
              response: { data: { error: 'stale_configuration_revision' } },
            });
        }
      }
    } finally {
      if (current(request, account)) saving.value = false;
    }
  };
  watch(
    () => String(accountId.value),
    () => {
      generation += 1;
      entries.value = [];
      baseline.value = [];
      saving.value = false;
      version.value = 0;
      load();
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    alive = false;
    generation += 1;
    entries.value = [];
    baseline.value = [];
    policy.value = null;
  });
  return {
    entries,
    baseline,
    version,
    loading,
    saving,
    error,
    saved,
    dirty,
    valid,
    canSave,
    revision,
    load,
    save,
  };
};
