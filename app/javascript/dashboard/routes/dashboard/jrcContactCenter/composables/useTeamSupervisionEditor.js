import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';

const identity = value =>
  typeof value === 'string' &&
  /^[1-9][0-9]{0,18}$/.test(value) &&
  (value.length < 19 || value <= '9223372036854775807');
const sortedIds = ids =>
  [...ids].sort(
    (left, right) => left.length - right.length || left.localeCompare(right)
  );
const validPerson = row =>
  identity(row?.account_user_id) &&
  typeof row.name === 'string' &&
  typeof row.eligible === 'boolean';
const validPage = value =>
  Number.isInteger(value?.page) &&
  value.page > 0 &&
  Number.isInteger(value.pages) &&
  value.pages >= 0 &&
  Number.isInteger(value.total) &&
  value.total >= 0;

export const useTeamSupervisionEditor = ({
  accountId,
  teamId,
  authority,
  onDenied,
  onSaved,
  onClose,
}) => {
  const selected = ref(null);
  const draft = ref({
    primary_account_user_id: null,
    additional_account_user_ids: [],
  });
  const known = ref({});
  const candidates = ref([]);
  const query = ref('');
  const page = ref(1);
  const meta = ref({ page: 1, pages: 0, total: 0 });
  const opening = ref(false);
  const loadingCandidates = ref(false);
  const saving = ref(false);
  const error = ref('');
  const candidateError = ref(false);
  const uncertain = ref(false);
  const reviewedDraft = ref('');
  const resource = ref('team_supervisions');
  let generation = 0;
  let listGeneration = 0;
  const fingerprint = () => JSON.stringify(draft.value);
  let revision;
  const selectedIds = computed(() =>
    [
      draft.value.primary_account_user_id,
      ...draft.value.additional_account_user_ids,
    ].filter(Boolean)
  );
  const reviewed = computed(() => reviewedDraft.value === fingerprint());
  const canSave = computed(
    () =>
      Boolean(selected.value) &&
      String(revision.state.id) === String(teamId.value) &&
      revision.state.required &&
      revision.canSave.value &&
      reviewed.value &&
      !opening.value &&
      !saving.value &&
      !uncertain.value &&
      selectedIds.value.every(id => known.value[id]?.eligible)
  );
  const presentation = computed(() => ({
    primary_supervisor:
      known.value[draft.value.primary_account_user_id]?.name || null,
    additional_supervisors: draft.value.additional_account_user_ids.map(
      id => known.value[id]?.name || id
    ),
  }));
  const remember = rows => {
    rows.forEach(row => {
      known.value[row.account_user_id] = row;
    });
  };
  const validItem = item =>
    item?.id === String(teamId.value) &&
    typeof item.revision === 'string' &&
    /^[0-9a-f]{64}$/.test(item.revision) &&
    (item.primary_account_user_id === null ||
      identity(item.primary_account_user_id)) &&
    Array.isArray(item.additional_account_user_ids) &&
    item.additional_account_user_ids.every(identity) &&
    Array.isArray(item.supervisors) &&
    item.supervisors.every(validPerson);
  const apply = item => {
    if (!validItem(item))
      throw new Error('Invalid native team supervision identity');
    remember(item.supervisors);
    selected.value = item;
    draft.value = {
      primary_account_user_id: item.primary_account_user_id,
      additional_account_user_ids: sortedIds(item.additional_account_user_ids),
    };
    revision.capture(item);
    reviewedDraft.value = '';
  };
  const clear = () => {
    generation += 1;
    listGeneration += 1;
    selected.value = null;
    draft.value = {
      primary_account_user_id: null,
      additional_account_user_ids: [],
    };
    known.value = {};
    candidates.value = [];
    query.value = '';
    page.value = 1;
    meta.value = { page: 1, pages: 0, total: 0 };
    opening.value = false;
    saving.value = false;
    loadingCandidates.value = false;
    error.value = '';
    candidateError.value = false;
    uncertain.value = false;
    reviewedDraft.value = '';
    revision.capture(null);
  };
  const denied = () => {
    clear();
    onDenied();
  };
  revision = useConfigurationRevision({
    accountId,
    resource,
    draft,
    onDenied: denied,
  });
  const loadCandidates = async (nextPage = 1) => {
    if (!selected.value || saving.value) return;
    listGeneration += 1;
    const current = generation;
    const list = listGeneration;
    loadingCandidates.value = true;
    candidateError.value = false;
    candidates.value = [];
    page.value = nextPage;
    try {
      const response = await API.teamSupervisionCandidates(
        accountId.value,
        teamId.value,
        {
          page: nextPage,
          per_page: 20,
          q: query.value,
        }
      );
      if (current !== generation || list !== listGeneration) return;
      if (
        response.data.account_id !== String(accountId.value) ||
        !Array.isArray(response.data.items) ||
        response.data.items.length > 20 ||
        !response.data.items.every(validPerson) ||
        !validPage(response.data.meta)
      )
        throw new Error('Invalid native supervisor candidates');
      remember(response.data.items);
      candidates.value = response.data.items;
      meta.value = response.data.meta;
    } catch (failure) {
      if (current !== generation || list !== listGeneration) return;
      if ([401, 403, 404].includes(failure?.response?.status)) denied();
      else candidateError.value = true;
    } finally {
      if (current === generation && list === listGeneration)
        loadingCandidates.value = false;
    }
  };
  const open = async () => {
    if (opening.value || saving.value) return;
    clear();
    const current = generation;
    opening.value = true;
    try {
      const response = await API.configurationRecord(
        accountId.value,
        resource.value,
        teamId.value
      );
      if (current !== generation) return;
      if (response.data.account_id !== String(accountId.value))
        throw new Error('Invalid native supervision account');
      apply(response.data.item);
      await loadCandidates();
    } catch (failure) {
      if (current !== generation) return;
      if ([401, 403, 404].includes(failure?.response?.status)) denied();
      else error.value = 'LOAD_ERROR';
    } finally {
      if (current === generation) opening.value = false;
    }
  };
  const choosePrimary = person => {
    if (saving.value || !person.eligible) return;
    remember([person]);
    draft.value.primary_account_user_id = person.account_user_id;
    draft.value.additional_account_user_ids =
      draft.value.additional_account_user_ids.filter(
        id => id !== person.account_user_id
      );
  };
  const chooseAdditional = (person, checked) => {
    if (saving.value) return;
    const id = person.account_user_id;
    if (!checked) {
      draft.value.additional_account_user_ids =
        draft.value.additional_account_user_ids.filter(value => value !== id);
      return;
    }
    if (
      !person.eligible ||
      id === draft.value.primary_account_user_id ||
      draft.value.additional_account_user_ids.length >= 128
    )
      return;
    remember([person]);
    draft.value.additional_account_user_ids = sortedIds([
      ...new Set([...draft.value.additional_account_user_ids, id]),
    ]);
  };
  const review = confirmed => {
    reviewedDraft.value = confirmed ? fingerprint() : '';
    revision.review(confirmed);
  };
  const reload = async () => {
    await revision.reload();
    if (!revision.state.latest) return;
    if (!validItem(revision.state.latest)) {
      revision.state.latest = null;
      revision.state.error = true;
      error.value = 'LOAD_ERROR';
      return;
    }
    remember(revision.state.latest.supervisors);
    uncertain.value = false;
    if (error.value === 'UNCERTAIN') error.value = '';
    reviewedDraft.value = '';
  };
  const useServer = () => {
    if (revision.state.latest) apply(revision.state.latest);
    uncertain.value = false;
    error.value = '';
  };
  const save = async () => {
    if (!canSave.value) return;
    const current = generation;
    saving.value = true;
    error.value = '';
    try {
      const response = await API.saveTeamSupervision(
        accountId.value,
        teamId.value,
        draft.value,
        revision.options()
      );
      if (current !== generation) return;
      if (response.data.account_id !== String(accountId.value))
        throw new Error('Invalid saved supervision account');
      apply(response.data.item);
      onSaved();
    } catch (failure) {
      if (current !== generation) return;
      if ([401, 403, 404].includes(failure?.response?.status)) {
        denied();
        return;
      }
      reviewedDraft.value = '';
      if (revision.handleError(failure)) return;
      if (
        !failure?.response ||
        failure.response.status >= 500 ||
        failure.response.status === 408
      ) {
        uncertain.value = true;
        revision.state.conflict = true;
        revision.state.latest = null;
        error.value = 'UNCERTAIN';
      } else
        error.value =
          failure?.response?.data?.error === 'ineligible_team_supervisor'
            ? 'INELIGIBLE'
            : 'SAVE_ERROR';
    } finally {
      if (current === generation) saving.value = false;
    }
  };
  watch(
    fingerprint,
    () => {
      reviewedDraft.value = '';
      revision.review(false);
    },
    { flush: 'sync' }
  );
  watch(
    [accountId, teamId, authority],
    () => {
      clear();
      onClose();
    },
    { flush: 'sync' }
  );
  onBeforeUnmount(() => {
    generation += 1;
    listGeneration += 1;
  });
  return {
    selected,
    draft,
    known,
    candidates,
    query,
    page,
    meta,
    opening,
    loadingCandidates,
    saving,
    error,
    candidateError,
    uncertain,
    reviewed,
    canSave,
    presentation,
    revision,
    open,
    clear,
    loadCandidates,
    choosePrimary,
    chooseAdditional,
    review,
    reload,
    useServer,
    save,
  };
};
