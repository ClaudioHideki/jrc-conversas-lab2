import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskClosureRevisions';
import LifecycleAPI from 'dashboard/api/serviceDeskLifecycle';
import { useOperationalScope } from './useOperationalScope';

export function useClosureRevision() {
  const { t } = useI18n();
  const unitId = ref('');
  const operatorId = ref('');
  const scope = useOperationalScope(
    unitId,
    context =>
      context?.capabilities?.lifecycle_policies?.publish === true &&
      [
        'tickets_view_all',
        'history_view',
        'sla_view',
        'contract_conditions_view',
      ].every(key =>
        context.effective_permissions?.includes(`jrc_service_desk_${key}`)
      )
  );
  const versions = ref([]);
  const versionPage = ref(1);
  const versionTotal = ref(0);
  const sourceId = ref('');
  const targetId = ref('');
  const proposal = ref(null);
  const rows = ref([]);
  const counts = ref({});
  const total = ref(0);
  const candidatesLoaded = ref(false);
  const page = ref(1);
  const selected = ref([]);
  const filters = ref({
    q: '',
    status_id: '',
    category_id: '',
    assignee_id: '',
    created_from: '',
    created_to: '',
  });
  const reviewed = ref(false);
  const reason = ref('');
  const reviewName = ref('');
  const preview = ref(null);
  const result = ref(null);
  const batchId = ref('');
  const previewOperation = ref(false);
  const busy = ref(false);
  const feedback = ref('');
  const source = computed(() =>
    versions.value.find(row => row.id === sourceId.value)
  );
  const eligible = computed(() => rows.value.filter(row => !row.reason));
  const changedRules = computed(() =>
    (proposal.value?.definition?.transitions || []).filter(row =>
      ['resolve', 'close'].includes(row.action)
    )
  );
  const storageKey = () =>
    `jrc-sd-closure-batch:${scope.identity.value}:${unitId.value}`;
  const code = value =>
    t(`JRC_SERVICE_DESK.CLOSURE_REVISION.reasons.${value || 'eligible'}`);
  const request = (lease, action, values = {}, opts = {}) =>
    API.request(
      lease.context.account_id,
      action,
      { unit_id: lease.unit, ...values },
      { signal: lease.signal, ...opts }
    );
  const operate = async action => {
    if (busy.value) return;
    const lease = scope.begin();
    if (!lease) return;
    busy.value = true;
    feedback.value = '';
    try {
      await action(lease);
    } catch {
      if (scope.live(lease)) feedback.value = 'failed';
    } finally {
      if (scope.live(lease)) busy.value = false;
    }
  };
  function checkResult(value) {
    if (
      !value ||
      typeof value.batch_id !== 'string' ||
      (batchId.value && value.batch_id !== batchId.value) ||
      typeof value.complete !== 'boolean' ||
      !Array.isArray(value.results) ||
      !value.results.every(
        row =>
          /^\d+$/.test(row.ticket_id) &&
          ['applied', 'blocked', 'conflict', 'pending'].includes(row.status)
      )
    )
      throw new TypeError('Invalid batch result');
    return value;
  }
  const loadVersions = async (lease, nextPage = 1) => {
    const data = await request(lease, 'versions', { page: nextPage });
    if (!scope.live(lease)) return;
    versions.value = [
      ...new Map(
        [...versions.value, ...data.versions].map(row => [row.id, row])
      ).values(),
    ];
    versionPage.value = nextPage;
    versionTotal.value = data.total;
  };
  const load = async (lease, targetPage = 1) => {
    const data = await request(lease, '', {
      source_version_id: sourceId.value,
      target_version_id: targetId.value,
      page: targetPage,
      filters: filters.value,
    });
    if (!scope.live(lease)) return;
    rows.value = data.items;
    counts.value = data.counts;
    total.value = data.total;
    candidatesLoaded.value = true;
    page.value = targetPage;
  };
  const propose = () =>
    operate(async lease => {
      const data = await request(
        lease,
        'proposal',
        { source_version_id: sourceId.value },
        { method: 'post' }
      );
      if (scope.live(lease)) proposal.value = data;
    });
  const publish = () =>
    operate(async lease => {
      const draft = proposal.value;
      const ack = await LifecycleAPI.publish(
        lease.context.account_id,
        lease.unit,
        {
          name: draft.name,
          service_id: draft.service_id,
          enabled: true,
          expected_version: draft.expected_version,
          definition: draft.definition,
        },
        lease.signal
      );
      if (!scope.live(lease)) return;
      await loadVersions(lease);
      if (!scope.live(lease)) return;
      const saved = versions.value.find(
        row =>
          row.id === ack.policy.version_id && row.digest === ack.policy.digest
      );
      if (!saved) throw new TypeError('Unconfirmed publication');
      targetId.value = saved.id;
      proposal.value = null;
      feedback.value = 'published';
    });
  const makePreview = () =>
    operate(async lease => {
      const data = await request(
        lease,
        'preview',
        {
          source_version_id: sourceId.value,
          target_version_id: targetId.value,
          ticket_ids: selected.value,
          operational_review: reviewed.value,
          review_reason: reason.value,
          review_name: reviewName.value,
        },
        { method: 'post' }
      );
      if (!scope.live(lease)) return;
      if (
        typeof data.preview?.receipt !== 'string' ||
        data.preview.tickets
          .map(row => row.id)
          .sort()
          .join() !== [...selected.value].sort().join()
      )
        throw new TypeError('Invalid selected cohort');
      preview.value = data.preview;
    });
  const readResult = async lease => {
    const data = await request(lease, 'result', {
      idempotency_key: batchId.value,
    });
    if (scope.live(lease)) result.value = checkResult(data.result);
  };
  const apply = () =>
    operate(async lease => {
      if (!preview.value) return;
      if (!previewOperation.value) {
        batchId.value = crypto.randomUUID();
        previewOperation.value = true;
      }
      localStorage.setItem(storageKey(), batchId.value);
      await request(
        lease,
        '',
        { receipt: preview.value.receipt },
        { method: 'post', key: batchId.value }
      );
      if (!scope.live(lease)) return;
      await readResult(lease);
      if (scope.live(lease)) feedback.value = 'confirmed';
    });
  const recover = () => operate(readResult);
  const resume = () =>
    operate(async lease => {
      await request(
        lease,
        'resume',
        { idempotency_key: batchId.value },
        { method: 'post' }
      );
      if (scope.live(lease)) await readResult(lease);
    });
  const resetPreview = () => {
    preview.value = null;
    result.value = null;
    previewOperation.value = false;
  };
  watch(
    [sourceId, targetId, selected, reviewed, reason, reviewName],
    resetPreview,
    {
      deep: true,
    }
  );
  watch(sourceId, () => {
    proposal.value = null;
    rows.value = [];
    selected.value = [];
  });
  watch(
    [scope.identity, unitId],
    () => {
      scope.cancel();
      versions.value = [];
      sourceId.value = '';
      targetId.value = '';
      proposal.value = null;
      rows.value = [];
      selected.value = [];
      counts.value = {};
      total.value = 0;
      candidatesLoaded.value = false;
      filters.value = {
        q: '',
        status_id: '',
        category_id: '',
        assignee_id: '',
        created_from: '',
        created_to: '',
      };
      reviewed.value = false;
      reason.value = '';
      preview.value = null;
      result.value = null;
      busy.value = false;
      try {
        batchId.value = localStorage.getItem(storageKey()) || '';
      } catch {
        batchId.value = '';
      }
      if (unitId.value) operate(lease => loadVersions(lease));
    },
    { flush: 'sync' }
  );

  const applyAsync = () =>
    operate(async lease => {
      if (!preview.value) return;
      if (!previewOperation.value) {
        batchId.value = crypto.randomUUID();
        previewOperation.value = true;
      }
      localStorage.setItem(storageKey(), batchId.value);
      const response = await request(
        lease,
        'enqueue',
        { receipt: preview.value.receipt },
        { method: 'post', key: batchId.value }
      );
      if (!scope.live(lease)) return;
      result.value = checkResult(response.result);
      feedback.value = result.value.complete ? 'confirmed' : 'dispatch_pending';
      if (!result.value.complete && response.queued === true)
        feedback.value = 'queued';
    });
  const resumeAsync = () =>
    operate(async lease => {
      const response = await request(
        lease,
        'resume_async',
        { idempotency_key: batchId.value },
        { method: 'post' }
      );
      if (scope.live(lease)) {
        result.value = checkResult(response.result);
        feedback.value = result.value.complete
          ? 'confirmed'
          : 'dispatch_pending';
        if (!result.value.complete && response.queued === true)
          feedback.value = 'queued';
      }
    });

  watch(
    filters,
    () => {
      selected.value = [];
      rows.value = [];
      counts.value = {};
      total.value = 0;
      candidatesLoaded.value = false;
      resetPreview();
    },
    { deep: true }
  );

  return {
    t,
    unitId,
    operatorId,
    scope,
    versions,
    versionPage,
    versionTotal,
    sourceId,
    targetId,
    proposal,
    rows,
    counts,
    total,
    candidatesLoaded,
    page,
    selected,
    filters,
    reviewed,
    reason,
    reviewName,
    preview,
    result,
    batchId,
    previewOperation,
    busy,
    feedback,
    source,
    eligible,
    changedRules,
    storageKey,
    code,
    request,
    operate,
    loadVersions,
    load,
    propose,
    publish,
    makePreview,
    readResult,
    apply,
    recover,
    resume,
    resetPreview,
    applyAsync,
    resumeAsync,
    checkResult,
  };
}
