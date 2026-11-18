import { computed, onBeforeUnmount, reactive, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';

const resources = [
  'units',
  'queues',
  'memberships',
  'access_users',
  'access_teams',
  'ivr_drafts',
  'acw_policy',
  'pause_catalog',
];
const validRevision = (value, resource) =>
  resource === 'ivr_drafts'
    ? Number.isInteger(value) && value > 0 && value <= 2147483647
    : typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
export const useConfigurationRevision = ({ accountId, resource, draft }) => {
  const state = reactive({
    account: '',
    resource: '',
    required: false,
    conflict: false,
    expected: '',
    latest: null,
    reloading: false,
    error: false,
    id: null,
    reviewedDraft: '',
  });
  let generation = 0;
  const fingerprint = () => JSON.stringify(draft.value);
  const reviewed = () =>
    Boolean(state.latest && state.reviewedDraft === fingerprint());
  const canSave = computed(
    () =>
      !state.required ||
      (state.account === String(accountId.value) &&
        state.resource === resource.value &&
        !state.reloading &&
        Boolean(state.expected) &&
        (!state.conflict || reviewed()))
  );
  const capture = record => {
    generation += 1;
    Object.assign(state, {
      account: String(accountId.value),
      resource: resource.value,
      required: Boolean(record?.id && resources.includes(resource.value)),
      conflict: false,
      expected: validRevision(record?.revision, resource.value)
        ? record.revision
        : '',
      latest: null,
      reloading: false,
      error: false,
      id: record?.id || null,
      reviewedDraft: '',
    });
    if (state.required && !state.expected) state.conflict = true;
  };
  const handleError = error => {
    const codes =
      resource.value === 'ivr_drafts'
        ? ['stale_ivr_revision', 'ivr_revision_required']
        : ['stale_configuration_revision', 'configuration_revision_required'];
    if (!state.required || !codes.includes(error?.response?.data?.error))
      return false;
    state.conflict = true;
    state.latest = null;
    state.reviewedDraft = '';
    state.error = false;
    return true;
  };
  const reload = async () => {
    if (!state.required || state.reloading) return;
    generation += 1;
    const version = generation;
    const account = String(accountId.value);
    const source = resource.value;
    const id = state.id;
    state.reloading = true;
    state.error = false;
    state.latest = null;
    state.reviewedDraft = '';
    try {
      let response;
      if (source === 'pause_catalog')
        response = await API.pauseCatalog(account);
      else if (source === 'acw_policy') response = await API.acwPolicy(account);
      else response = await API.configurationRecord(account, source, id);
      if (
        version !== generation ||
        account !== String(accountId.value) ||
        source !== resource.value ||
        id !== state.id
      )
        return;
      const latest = response.data.item;
      if (
        !validRevision(latest.revision, source) ||
        String(latest.id) !== String(id)
      )
        throw new Error('Invalid revision response');
      state.expected = latest.revision;
      state.latest = latest;
    } catch {
      if (version === generation) state.error = true;
    } finally {
      if (version === generation) state.reloading = false;
    }
  };
  const review = confirmed => {
    state.reviewedDraft = confirmed ? fingerprint() : '';
  };
  const options = () =>
    state.required ? { expected_revision: state.expected } : {};
  watch(
    () => String(accountId.value) + ':' + resource.value,
    () => capture(null)
  );
  onBeforeUnmount(() => {
    generation += 1;
  });
  return {
    state,
    canSave,
    capture,
    handleError,
    reload,
    reviewed,
    review,
    options,
  };
};
