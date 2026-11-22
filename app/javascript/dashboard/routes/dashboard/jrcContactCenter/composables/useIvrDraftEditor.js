import { clearIvrCalendarReferences } from '../helpers/ivrCalendar';
import { computed, onBeforeUnmount, reactive, ref } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';
import {
  emptyIvr,
  parseIvrDraft,
  clearIvrQueues,
  clearIvrAudioReferences,
} from '../helpers/ivrDraft';

export const useIvrDraftEditor = ({ accountId, initialId }) => {
  const draft = ref({
    name: '',
    unit_id: '',
    status: 'draft',
    revision: 0,
    definition: emptyIvr(),
  });
  const recordId = ref(initialId || null);
  const state = reactive({
    loading: false,
    loaded: !initialId,
    saving: false,
    denied: false,
    error: '',
    saved: false,
    uncertain: false,
    timezone: null,
  });
  const jsonText = ref(JSON.stringify(draft.value.definition, null, 2));
  const jsonPending = ref(false);
  const baseline = ref(JSON.stringify(draft.value));
  const resource = computed(() => 'ivr_drafts');
  const revision = useConfigurationRevision({ accountId, resource, draft });
  const dirty = computed(
    () => jsonPending.value || JSON.stringify(draft.value) !== baseline.value
  );
  const busy = computed(() => state.loading || state.saving);
  const locked = computed(
    () => busy.value || !state.loaded || state.denied || state.uncertain
  );
  const canSave = computed(
    () =>
      !busy.value &&
      state.loaded &&
      !state.denied &&
      !state.uncertain &&
      !jsonPending.value &&
      revision.canSave.value
  );
  let generation = 0;
  let pendingBody = null;
  let pendingFingerprint = '';
  let pendingTarget = null;

  const hydrate = item => {
    const graph = parseIvrDraft(JSON.stringify(item.definition));
    draft.value = {
      name: item.name,
      unit_id: String(item.unit_id),
      status: item.status,
      revision: item.revision,
      definition: graph,
    };
    recordId.value = item.id;
    jsonText.value = JSON.stringify(graph, null, 2);
    jsonPending.value = false;
    baseline.value = JSON.stringify(draft.value);
    revision.capture(item);
    state.loaded = true;
    state.denied = false;
  };
  const load = async () => {
    if (!recordId.value || state.saving) return;
    generation += 1;
    const version = generation;
    state.loading = true;
    state.loaded = false;
    state.error = '';
    try {
      const response = await API.configurationRecord(
        accountId.value,
        'ivr_drafts',
        recordId.value
      );
      if (version === generation) {
        state.timezone = response.data.timezone;
        hydrate(response.data.item);
      }
    } catch {
      if (version === generation) state.error = 'LOAD_FAILED';
    } finally {
      if (version === generation) state.loading = false;
    }
  };
  const changed = () => {
    state.saved = false;
    state.error = '';
  };
  const setGraph = graph => {
    draft.value.definition = graph;
    jsonText.value = JSON.stringify(graph, null, 2);
    jsonPending.value = false;
    changed();
  };
  const setUnit = id => {
    if (recordId.value) return;
    draft.value.unit_id = id;
    const graph = JSON.parse(JSON.stringify(draft.value.definition));
    clearIvrQueues(graph);
    clearIvrAudioReferences(graph);
    clearIvrCalendarReferences(graph);
    setGraph(graph);
  };
  const applyJson = text => {
    const graph = parseIvrDraft(text);
    setGraph(graph);
  };
  const discardJson = () => {
    jsonText.value = JSON.stringify(draft.value.definition, null, 2);
    jsonPending.value = false;
  };
  const save = async (status = 'draft', retry = false) => {
    if (state.saving || state.loading || (!retry && !canSave.value))
      return false;
    if (retry && (!state.uncertain || !pendingBody)) return false;
    if (!retry && (!draft.value.name.trim() || !draft.value.unit_id)) {
      state.error = 'REQUIRED';
      return false;
    }
    generation += 1;
    const version = generation;
    const account = String(accountId.value);
    let body = pendingBody;
    let target = pendingTarget;
    if (!retry) {
      body = {
        name: draft.value.name,
        unit_id: draft.value.unit_id,
        status,
        definition: draft.value.definition,
        expected_revision: recordId.value
          ? revision.options().expected_revision
          : 0,
      };
      const fingerprint = JSON.stringify(body);
      const requestId =
        fingerprint === pendingFingerprint && pendingBody
          ? pendingBody.request_id
          : crypto.randomUUID();
      body = JSON.parse(JSON.stringify({ ...body, request_id: requestId }));
      target = recordId.value;
      pendingBody = body;
      pendingTarget = target;
      pendingFingerprint = fingerprint;
    }
    state.saving = true;
    state.error = '';
    state.saved = false;
    try {
      const response = await API.saveIvrDraft(account, target, body);
      if (version !== generation || account !== String(accountId.value))
        return false;
      recordId.value = response.data.item.id;
      state.uncertain = false;
      state.loaded = false;
      const latest = await API.configurationRecord(
        account,
        'ivr_drafts',
        recordId.value
      );
      if (version !== generation || account !== String(accountId.value))
        return false;
      state.timezone = latest.data.timezone;
      hydrate(latest.data.item);
      pendingBody = null;
      pendingFingerprint = '';
      state.saved = true;
      return true;
    } catch (error) {
      if (version !== generation) return false;
      if (revision.handleError(error)) state.error = '';
      else if ([401, 403, 404].includes(error?.response?.status)) {
        state.denied = true;
        state.error = 'DENIED';
      } else if (
        error?.response?.status === 409 &&
        [
          'ivr_audio_not_verified',
          'ivr_calendar_changed',
          'ivr_calendar_attestation_conflict',
        ].includes(error.response.data?.error)
      ) {
        state.uncertain = false;
        state.error = error.response.data.error;
      } else if (error?.response?.status === 422)
        state.error = error.response.data.error || 'SAVE_FAILED';
      else {
        state.uncertain = true;
        state.error = 'UNCERTAIN';
      }
      return false;
    } finally {
      if (version === generation) state.saving = false;
    }
  };
  onBeforeUnmount(() => {
    generation += 1;
    pendingBody = null;
  });
  return {
    draft,
    recordId,
    state,
    jsonText,
    jsonPending,
    revision,
    dirty,
    busy,
    locked,
    canSave,
    load,
    changed,
    setGraph,
    setUnit,
    applyJson,
    discardJson,
    save,
  };
};
