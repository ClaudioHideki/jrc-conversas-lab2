import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { useConfigurationRevision } from './useConfigurationRevision';

const copy = value => JSON.parse(JSON.stringify(value));
const digest = value =>
  typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const denied = failure => [401, 403, 404].includes(failure?.response?.status);
const blank = () => ({
  code: '',
  name: '',
  reason_code: '',
  queue_id: '',
  scope_revision: '',
  timing: '',
  execution_mode: '',
  active: false,
  conditions: { outcome_codes: [] },
  actions: [],
});
const editable = row => ({
  ...copy(row),
  scope_revision: row.scope.integrity_sha256,
  execution_mode: row.execution_mode || '',
});

export const useEndingAutomationEditor = ({ accountId }) => {
  const items = ref([]);
  const meta = ref({ page: 1, pages: 0, total: 0 });
  const q = ref('');
  const status = ref('all');
  const page = ref(1);
  const policy = ref(null);
  const destinationPresentations = ref({});
  const draft = ref(null);
  const baseline = ref('');
  const persisted = ref(false);
  const activationRevision = ref('');
  const source = ref(null);
  const loading = ref(false);
  const saving = ref(false);
  const sourceLoading = ref(false);
  const error = ref('');
  const reviewed = ref(false);
  const saved = ref(false);
  let generation = 0;
  let sourceGeneration = 0;
  let alive = true;
  const current = (request, account) =>
    alive && request === generation && account === String(accountId.value);
  const dirty = computed(() =>
    Boolean(draft.value && JSON.stringify(draft.value) !== baseline.value)
  );
  const reasons = computed(
    () => policy.value?.voice_reason_catalog?.entries || []
  );
  const crmOptions = computed(() => {
    const value = policy.value?.destination_options?.crm;
    return value?.configuration_available === true &&
      Array.isArray(value.activity_types)
      ? value
      : { configuration_available: false, activity_types: [] };
  });
  const serviceDeskOptions = computed(() => {
    const value = source.value?.service_desk;
    return source.value?.configuration_available === true &&
      value?.configuration_available === true &&
      value.unit
      ? value
      : { configuration_available: false };
  });
  const reset = () => {
    sourceGeneration += 1;
    items.value = [];
    draft.value = null;
    source.value = null;
    policy.value = null;
    destinationPresentations.value = {};
    activationRevision.value = '';
    baseline.value = '';
    reviewed.value = false;
    sourceLoading.value = false;
  };
  const checkAccount = (response, account) => {
    if (String(response.data.account_id) !== account)
      throw new Error('Invalid account response');
  };
  let revision;
  const deny = () => {
    reset();
    revision.capture(null);
    error.value = 'DENIED';
  };
  const reloadRecord = async (account, identity) => {
    const isNew = identity === 'new';
    const code = isNew ? '' : identity.slice('rule:'.length);
    const response = await API.endingRules(account, {
      rule_code: code,
      page: 1,
      per_page: 1,
    });
    checkAccount(response, account);
    const row = isNew
      ? blank()
      : response.data.items.find(item => item.code === code);
    if (!row)
      throw Object.assign(new Error('Rule unavailable'), {
        response: { status: 404 },
      });
    const queue = draft.value.queue_id;
    const context = queue
      ? await API.endingRuleSourceContext(account, queue)
      : null;
    if (context) checkAccount(context, account);
    return {
      data: {
        item: {
          ...row,
          id: identity,
          revision: response.data.revision,
          source_queue_id: queue,
          source_scope_revision: context?.data.item.scope_revision || '',
        },
      },
    };
  };
  revision = useConfigurationRevision({
    accountId,
    resource: computed(() => 'ending_rules'),
    draft,
    reloadRecord,
    onDenied: deny,
  });
  const load = async (requestedPage = page.value) => {
    if (saving.value || dirty.value) return;
    generation += 1;
    const request = generation;
    const account = String(accountId.value);
    loading.value = true;
    error.value = '';
    items.value = [];
    destinationPresentations.value = {};
    try {
      const response = await API.endingRules(account, {
        q: q.value,
        status: status.value,
        page: requestedPage,
        per_page: 10,
      });
      if (!current(request, account)) return;
      checkAccount(response, account);
      const configuration = response.data.editor_context;
      if (
        !configuration ||
        !Array.isArray(configuration.voice_reason_catalog?.entries) ||
        !digest(response.data.revision) ||
        response.data.revision !== configuration.revision ||
        String(configuration.id) !== account ||
        !Array.isArray(response.data.items)
      )
        throw new Error('Configuration changed while loading');
      const hasCrm = response.data.items.some(row =>
        row.actions.some(action => action.kind === 'crm')
      );
      if (
        hasCrm &&
        configuration.destination_options?.crm?.configuration_available !== true
      )
        throw Object.assign(
          new Error('Native CRM authority context unavailable'),
          {
            response: { status: 403 },
          }
        );
      const labels = response.data.destination_presentations || {};
      const missingLabels = response.data.items.some(
        row =>
          row.actions.some(action => action.kind === 'service_desk') &&
          !labels[row.code]?.service_desk
      );
      if (missingLabels)
        throw Object.assign(
          new Error('Native destination reference context unavailable'),
          { response: { status: 403 } }
        );
      destinationPresentations.value = labels;
      policy.value = configuration;
      items.value = response.data.items;
      meta.value = response.data.meta;
      page.value = requestedPage;
    } catch (failure) {
      if (current(request, account)) {
        if (denied(failure)) deny();
        else error.value = 'LOAD_FAILED';
      }
    } finally {
      if (current(request, account)) loading.value = false;
    }
  };
  const selectQueue = async (id, preserveDraftScope = false) => {
    sourceGeneration += 1;
    const request = sourceGeneration;
    const account = String(accountId.value);
    source.value = null;
    sourceLoading.value = false;
    if (!draft.value) return;
    draft.value.queue_id = id;
    if (!preserveDraftScope) draft.value.scope_revision = '';
    if (!id) return;
    sourceLoading.value = true;
    try {
      const response = await API.endingRuleSourceContext(account, id);
      if (
        !alive ||
        request !== sourceGeneration ||
        account !== String(accountId.value)
      )
        return;
      checkAccount(response, account);
      if (!digest(response.data.item.scope_revision))
        throw new Error('Missing source revision');
      source.value = response.data.item;
      if (!preserveDraftScope)
        draft.value.scope_revision = source.value.scope_revision;
    } catch (failure) {
      if (request === sourceGeneration && account === String(accountId.value)) {
        if (denied(failure)) deny();
        else error.value = 'SOURCE_FAILED';
      }
    } finally {
      if (request === sourceGeneration) sourceLoading.value = false;
    }
  };
  const edit = async row => {
    if (loading.value || saving.value || dirty.value || !policy.value) return;
    draft.value = row ? editable(row) : blank();
    activationRevision.value = row ? policy.value.revision : '';
    if (row) delete draft.value.scope;
    persisted.value = Boolean(row);
    baseline.value = JSON.stringify(draft.value);
    saved.value = false;
    error.value = '';
    reviewed.value = false;
    revision.capture({
      id: row ? `rule:${row.code}` : 'new',
      revision: policy.value.revision,
    });
    if (row) await selectQueue(row.queue_id, true);
  };
  const reviewConflict = confirmed => {
    const latest = revision.state.latest;
    if (confirmed && latest?.source_queue_id === draft.value?.queue_id)
      draft.value.scope_revision = latest.source_scope_revision;
    revision.review(confirmed);
  };
  const valid = computed(() => {
    const row = draft.value;
    return (
      row &&
      ['code', 'name', 'reason_code', 'queue_id'].every(
        key =>
          typeof row[key] === 'string' &&
          row[key].trim() === row[key] &&
          row[key]
      ) &&
      ['call_end', 'acw_completed'].includes(row.timing) &&
      ['automatic', 'agent_confirmation'].includes(row.execution_mode) &&
      digest(row.scope_revision) &&
      (!row.active || row.actions.length > 0) &&
      row.actions.every(
        action =>
          action.kind === 'project_task' ||
          (row.destination_schema_version === 2 &&
            action.kind === 'crm' &&
            crmOptions.value.configuration_available) ||
          (row.destination_schema_version === 2 &&
            action.kind === 'service_desk' &&
            serviceDeskOptions.value.configuration_available)
      ) &&
      (!row.active ||
        (source.value?.configuration_available &&
          reasons.value.some(
            reason => reason.code === row.reason_code && reason.active
          )))
    );
  });
  const canSave = computed(
    () =>
      valid.value &&
      dirty.value &&
      reviewed.value &&
      !loading.value &&
      !saving.value &&
      !sourceLoading.value &&
      revision.canSave.value
  );
  const save = async () => {
    if (!canSave.value) return;
    const request = generation;
    const account = String(accountId.value);
    const submitted = copy(draft.value);
    saving.value = true;
    error.value = '';
    saved.value = false;
    try {
      const response = await API.saveEndingRule(
        account,
        submitted,
        revision.options().expected_revision
      );
      if (!current(request, account)) return;
      checkAccount(response, account);
      if (
        response.data.item.code !== submitted.code ||
        !digest(response.data.revision)
      )
        throw new Error('Invalid saved rule');
      policy.value.revision = response.data.revision;
      activationRevision.value = response.data.revision;
      draft.value = editable(response.data.item);
      delete draft.value.scope;
      baseline.value = JSON.stringify(draft.value);
      persisted.value = true;
      reviewed.value = false;
      saved.value = true;
      revision.capture({
        id: `rule:${submitted.code}`,
        revision: response.data.revision,
      });
    } catch (failure) {
      if (current(request, account)) {
        if (denied(failure)) deny();
        else if (!revision.handleError(failure)) {
          error.value =
            failure?.response?.status === 422 ? 'INVALID' : 'SAVE_FAILED';
          if (
            !failure.response ||
            failure.response.status >= 500 ||
            failure.response.status === 409
          )
            revision.handleError({
              response: { data: { error: 'stale_configuration_revision' } },
            });
        }
      }
    } finally {
      if (current(request, account)) saving.value = false;
    }
  };
  const discard = async () => {
    if (saving.value) return;
    activationRevision.value = '';
    draft.value = null;
    source.value = null;
    sourceGeneration += 1;
    revision.capture(null);
    await load();
  };
  watch(
    () => JSON.stringify(draft.value),
    () => {
      reviewed.value = false;
    }
  );
  watch(
    () => String(accountId.value),
    () => {
      generation += 1;
      reset();
      saving.value = false;
      saved.value = false;
      page.value = 1;
      q.value = '';
      status.value = 'all';
      revision.capture(null);
      load(1);
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    alive = false;
    generation += 1;
    reset();
  });
  return {
    items,
    meta,
    q,
    status,
    page,
    draft,
    persisted,
    source,
    reasons,
    crmOptions,
    serviceDeskOptions,
    destinationPresentations,
    loading,
    saving,
    sourceLoading,
    error,
    reviewed,
    saved,
    dirty,
    canSave,
    revision,
    activationRevision,
    load,
    edit,
    selectQueue,
    reviewConflict,
    save,
    discard,
    deny,
  };
};
