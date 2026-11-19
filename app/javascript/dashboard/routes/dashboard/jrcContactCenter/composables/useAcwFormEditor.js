import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';
import { acwFormDefinition } from '../helpers/acwForms';

export const useAcwFormEditor = ({ accountId }) => {
  const draft = ref(null);
  const recordId = ref(null);
  const state = reactive({
    loading: false,
    saving: false,
    denied: false,
    uncertain: false,
    error: '',
    saved: false,
  });
  const revision = useConfigurationRevision({
    accountId,
    resource: computed(() => 'acw_forms'),
    draft,
  });
  const baseline = ref('');
  const dirty = computed(
    () => draft.value && JSON.stringify(draft.value) !== baseline.value
  );
  const busy = computed(() => state.loading || state.saving);
  const locked = computed(
    () => busy.value || state.denied || state.uncertain || !draft.value
  );
  const valid = computed(() => {
    if (!draft.value?.name.trim()) return false;
    try {
      acwFormDefinition(draft.value.definition);
      return true;
    } catch {
      return false;
    }
  });
  const canSave = computed(
    () => !locked.value && valid.value && revision.canSave.value
  );
  let generation = 0;
  let pending = null;
  const hydrate = item => {
    draft.value = {
      name: item.name,
      description: item.description,
      status: item.status,
      definition: acwFormDefinition(item.definition),
    };
    recordId.value = item.id;
    baseline.value = JSON.stringify(draft.value);
    revision.capture(item);
  };
  const reset = () => {
    generation += 1;
    draft.value = null;
    recordId.value = null;
    baseline.value = '';
    pending = null;
    revision.capture(null);
    Object.assign(state, {
      loading: false,
      saving: false,
      denied: false,
      uncertain: false,
      error: '',
      saved: false,
    });
  };
  const open = async id => {
    if (busy.value || state.uncertain) return false;
    reset();
    if (!id) {
      draft.value = {
        name: '',
        description: '',
        status: 'active',
        definition: { fields: [] },
      };
      baseline.value = JSON.stringify(draft.value);
      return true;
    }
    const version = generation;
    const account = String(accountId.value);
    state.loading = true;
    try {
      const response = await API.configurationRecord(account, 'acw_forms', id);
      if (version !== generation || account !== String(accountId.value))
        return false;
      hydrate(response.data.item);
      return true;
    } catch (error) {
      if (version === generation) {
        state.denied = [401, 403, 404].includes(error?.response?.status);
        state.error = state.denied ? 'DENIED' : 'LOAD_FAILED';
      }
      return false;
    } finally {
      if (version === generation) state.loading = false;
    }
  };
  const save = async (status = 'active', retry = false) => {
    if (busy.value || (retry ? !state.uncertain || !pending : !canSave.value))
      return false;
    if (!retry && status === 'archived' && (dirty.value || !recordId.value))
      return false;
    generation += 1;
    const version = generation;
    const account = String(accountId.value);
    if (!retry)
      pending = {
        account,
        id: recordId.value,
        body: JSON.parse(
          JSON.stringify({
            ...draft.value,
            status,
            expected_revision: recordId.value
              ? revision.options().expected_revision
              : 0,
            request_id: crypto.randomUUID(),
          })
        ),
      };
    if (pending.account !== account) return false;
    state.saving = true;
    state.error = '';
    state.saved = false;
    try {
      const response = await API.saveAcwForm(account, pending.id, pending.body);
      if (version !== generation || account !== String(accountId.value))
        return false;
      const latest = await API.configurationRecord(
        account,
        'acw_forms',
        response.data.item.id
      );
      if (version !== generation || account !== String(accountId.value))
        return false;
      hydrate(latest.data.item);
      pending = null;
      state.uncertain = false;
      state.saved = true;
      return true;
    } catch (error) {
      if (version !== generation || account !== String(accountId.value))
        return false;
      if (revision.handleError(error)) {
        pending = null;
        state.uncertain = false;
      } else if ([401, 403, 404].includes(error?.response?.status)) {
        state.denied = true;
        state.error = 'DENIED';
        pending = null;
      } else if ([400, 422, 428].includes(error?.response?.status)) {
        state.error = 'SAVE_FAILED';
        state.uncertain = false;
        pending = null;
      } else {
        state.uncertain = true;
        state.error = 'UNCERTAIN';
      }
      return false;
    } finally {
      if (version === generation) state.saving = false;
    }
  };
  watch(() => String(accountId.value), reset);
  onBeforeUnmount(() => {
    generation += 1;
    pending = null;
  });
  return {
    draft,
    recordId,
    state,
    revision,
    dirty,
    busy,
    locked,
    canSave,
    open,
    save,
    reset,
  };
};
