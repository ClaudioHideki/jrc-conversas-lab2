<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEndingAttemptHistory } from './useEndingAttemptHistory';
import { usePendingEndingRun } from './usePendingEndingRun';
import PendingEndingReview from './PendingEndingReview.vue';
import { destinationHistoryRoute } from './endingDestinationHistoryContract';
import { useEndingDestinationRequests } from './useEndingDestinationRequests';
import EndingTaskState from './EndingTaskState.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  qualificationId: { type: [String, Number], required: true },
  authorityKey: { type: String, required: true },
  readOnly: { type: Boolean, default: false },
});
const { t } = useI18n();
const labels = computed(() => ({
  OPEN: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.OPEN'),
  TITLE: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.TITLE'),
  CLOSE: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.CLOSE'),
  READ_ONLY: t('JRC_CONTACT_CENTER.ENDING_PENDING.HISTORY_HINT'),
  LOADING: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.LOADING'),
  DENIED: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.DENIED'),
  LOAD_FAILED: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.LOAD_FAILED'),
  EMPTY: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.EMPTY'),
  CALL: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.CALL'),
  VERSION: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.VERSION'),
  REQUEST: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.REQUEST'),
  QUEUED: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.QUEUED'),
  PENDING: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.PENDING'),
  SUCCEEDED: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.SUCCEEDED'),
  FAILED: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.FAILED'),
  BLOCKED: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.BLOCKED'),
  OPEN_TASK: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.OPEN_TASK'),
  OPEN_TARGET: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.OPEN_TARGET'),
  TARGET_UNAVAILABLE: t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.TARGET_UNAVAILABLE'
  ),
  REFRESH: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.REFRESH'),
  PREVIOUS: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.ENDING_ATTEMPTS.NEXT'),
  'RESULTS.completed': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.completed'
  ),
  'RESULTS.destination_failure': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.destination_failure'
  ),
  'RESULTS.authorization_denied': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.authorization_denied'
  ),
  'RESULTS.reference_unavailable': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.reference_unavailable'
  ),
  'RESULTS.deactivated': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.deactivated'
  ),
  'RESULTS.confirmation_required': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.confirmation_required'
  ),
  'RESULTS.trigger_pending': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.trigger_pending'
  ),
  'RESULTS.operation_unavailable': t(
    'JRC_CONTACT_CENTER.ENDING_ATTEMPTS.RESULTS.operation_unavailable'
  ),
}));
const text = key => labels.value[key];
const history = useEndingAttemptHistory({
  contractVersion: 2,
  accountId: computed(() => props.accountId),
  qualificationId: computed(() => props.qualificationId),
  authorityKey: computed(() => props.authorityKey),
});
const { opened, items, callSessionId, meta, loading, error } = history;
const pending = usePendingEndingRun({
  accountId: computed(() => props.accountId),
  qualificationId: computed(() => props.qualificationId),
  authorityKey: computed(() => props.authorityKey),
  enabled: computed(() => opened.value && !props.readOnly),
  onComplete: () => history.load(meta.value?.page || 1),
  onDenied: () => history.close(),
});
const {
  selected,
  reviewed,
  busy: pendingBusy,
  error: pendingError,
  canSubmit,
} = pending;
const manual = useEndingDestinationRequests({
  accountId: computed(() => props.accountId),
  qualificationId: computed(() => props.qualificationId),
  authorityKey: computed(() => props.authorityKey),
  enabled: computed(() => opened.value && !props.readOnly),
  onAccepted: () => history.load(meta.value?.page || 1),
  onDenied: () => history.close(),
});
const {
  items: manualItems,
  meta: manualMeta,
  loading: manualLoading,
  selected: manualSelected,
  reviewed: manualReviewed,
  busy: manualBusy,
  error: manualError,
  recorded: manualRecorded,
  canSubmit: manualCanSubmit,
} = manual;
const manualLabelPrefix = computed(() => {
  const mode = manualSelected.value?.mode;
  if (mode === 'retry') return 'JRC_CONTACT_CENTER.ENDING_TYPED_RETRY';
  if (mode === 'resume') return 'JRC_CONTACT_CENTER.ENDING_TYPED_RESUME';
  return 'JRC_CONTACT_CENTER.ENDING_MANUAL_ACTION';
});
const manualMessage = computed(() =>
  manualError.value
    ? t(
        `JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.ERRORS.${manualError.value}`
      )
    : ''
);
const manualReviewOperation = computed(() =>
  manualSelected.value
    ? {
        ...manualSelected.value,
        request_id:
          manualSelected.value.request_id ||
          manualSelected.value.new_request_id,
      }
    : null
);
const controlsLocked = computed(
  () =>
    loading.value ||
    pendingBusy.value ||
    manualBusy.value ||
    Boolean(selected.value || manualSelected.value)
);
const pendingLabels = computed(() => ({
  RUN: t('JRC_CONTACT_CENTER.ENDING_PENDING.RUN'),
  DENIED: t('JRC_CONTACT_CENTER.ENDING_PENDING.DENIED'),
  CHANGED: t('JRC_CONTACT_CENTER.ENDING_PENDING.CHANGED'),
  UNKNOWN: t('JRC_CONTACT_CENTER.ENDING_PENDING.UNKNOWN'),
  NATIVE_REFUSAL: t('JRC_CONTACT_CENTER.ENDING_PENDING.NATIVE_REFUSAL'),
}));
const pendingMessage = computed(
  () => pendingLabels.value[pendingError.value] || ''
);
const stateClasses = {
  pending: 'bg-n-blue-2 text-n-blue-11',
  succeeded: 'bg-n-teal-2 text-n-teal-11',
  failed: 'bg-n-ruby-2 text-n-ruby-11',
  blocked: 'bg-n-amber-2 text-n-amber-12 dark:text-n-amber-11',
};
const targetRoute = row => destinationHistoryRoute(row.target, props.accountId);
const reviewLegacyPending = row => {
  if (row.ledger === 'legacy') pending.open({ ...row, id: row.attempt_id });
};
const operationLabel = row =>
  t(
    `JRC_CONTACT_CENTER.ENDING_ATTEMPTS.OPERATIONS.${row.operation || 'create_task'}`
  );
</script>

<template>
  <section class="mt-3 min-w-0 space-y-3" data-ending-attempt-history>
    <p
      v-if="pendingMessage && !selected"
      role="alert"
      class="break-words text-sm text-n-ruby-11"
    >
      {{ pendingMessage }}
    </p>
    <PendingEndingReview
      v-if="!readOnly && selected"
      v-model:reviewed="reviewed"
      :operation="selected"
      :busy="pendingBusy"
      :can-submit="canSubmit"
      :message="pendingMessage"
      @confirm="pending.submit()"
      @close="pending.cancel()"
    />
    <PendingEndingReview
      v-if="!readOnly && manualSelected"
      v-model:reviewed="manualReviewed"
      :operation="manualReviewOperation"
      :busy="manualBusy"
      :can-submit="manualCanSubmit"
      :message="manualMessage"
      :label-prefix="manualLabelPrefix"
      @confirm="manual.submit()"
      @close="manual.cancel()"
    >
      <p class="break-words text-sm">{{ operationLabel(manualSelected) }}</p>
      <p
        v-if="manualSelected.mode === 'retry'"
        class="break-all text-xs text-n-slate-11"
      >
        {{ t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.NEW_REQUEST') }}:
        {{ manualSelected.new_request_id }}
      </p>
    </PendingEndingReview>
    <button
      v-if="!opened"
      type="button"
      class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-blue-11"
      data-open-ending-attempt-history
      @click="history.open()"
    >
      {{ text('OPEN') }}
    </button>
    <template v-else>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h4 class="text-sm font-semibold">{{ text('TITLE') }}</h4>
        <button
          type="button"
          class="rounded-lg border border-n-weak px-3 py-2 text-xs"
          :disabled="pendingBusy || manualBusy"
          @click="history.close()"
        >
          {{ text('CLOSE') }}
        </button>
      </div>
      <p class="text-xs text-n-slate-11">{{ text('READ_ONLY') }}</p>
      <p v-if="loading" role="status" class="text-sm text-n-slate-11">
        {{ text('LOADING') }}
      </p>
      <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ text(error) }}
      </p>
      <template v-else>
        <p v-if="callSessionId" class="break-all text-xs text-n-slate-11">
          {{ text('CALL') }}: {{ callSessionId }}
        </p>
        <p v-if="!items.length" class="text-sm text-n-slate-11">
          {{ text('EMPTY') }}
        </p>
        <article
          v-for="row in items"
          :key="row.id"
          class="min-w-0 space-y-2 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm"
          data-ending-attempt-row
        >
          <p class="break-words font-semibold">{{ row.rule_code }}</p>
          <p class="text-xs text-n-slate-11" data-ending-attempt-operation>
            {{ operationLabel(row) }}
          </p>
          <p
            class="inline-flex rounded-md px-2 py-1 text-xs font-semibold"
            :class="stateClasses[row.outcome]"
            data-ending-attempt-state
          >
            {{ text(row.outcome.toUpperCase()) }}
          </p>
          <p v-if="row.result_code" class="text-xs text-n-slate-11">
            {{ text(`RESULTS.${row.result_code}`) }}
          </p>
          <dl class="grid min-w-0 grid-cols-1 gap-2 text-xs">
            <div>
              <dt class="text-n-slate-10">{{ text('VERSION') }}</dt>
              <dd class="break-all">{{ row.version_id }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-10">{{ text('REQUEST') }}</dt>
              <dd class="break-all">{{ row.request_id }}</dd>
            </div>
            <div>
              <dt class="text-n-slate-10">{{ text('QUEUED') }}</dt>
              <dd class="break-all">{{ row.queued_at }}</dd>
            </div>
          </dl>
          <button
            v-if="!readOnly && row.can_reprocess_pending"
            type="button"
            :disabled="controlsLocked"
            class="max-w-full whitespace-normal rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
            data-review-selected-ending-pending
            @click="reviewLegacyPending(row)"
          >
            {{ pendingLabels.RUN }}
          </button>
          <button
            v-if="!readOnly && row.can_resume_pending"
            type="button"
            :disabled="controlsLocked"
            class="max-w-full whitespace-normal rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
            data-resume-selected-ending-destination
            @click="manual.openResume(row)"
          >
            {{ t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.RESUME') }}
          </button>
          <button
            v-if="!readOnly && row.can_retry_selected"
            type="button"
            :disabled="controlsLocked"
            class="max-w-full whitespace-normal rounded-lg border border-n-amber-7 bg-n-amber-2 px-3 py-2 text-sm text-n-amber-12 dark:text-n-amber-11 disabled:opacity-40"
            data-retry-selected-ending-destination
            @click="manual.openRetry(row)"
          >
            {{ t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.RETRY') }}
          </button>
          <EndingTaskState
            v-if="row.target?.kind === 'project_task'"
            :account-id="accountId"
            :project-id="row.target.project_id"
            :task-id="row.target.id"
            :authority-key="authorityKey"
          />
          <router-link
            v-if="targetRoute(row)"
            :to="targetRoute(row)"
            class="inline-flex rounded-lg border border-n-weak px-3 py-2 text-n-blue-11"
            data-ending-attempt-target
          >
            {{
              text(
                row.target.kind === 'project_task' ? 'OPEN_TASK' : 'OPEN_TARGET'
              )
            }}
          </router-link>
          <p
            v-else-if="row.outcome === 'succeeded'"
            class="text-xs text-n-slate-11"
          >
            {{ text('TARGET_UNAVAILABLE') }}
          </p>
        </article>
      </template>
      <section
        v-if="!readOnly"
        class="min-w-0 space-y-2"
        data-manual-ending-actions
      >
        <h5 class="text-sm font-semibold">
          {{ t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.TITLE') }}
        </h5>
        <p
          v-if="manualMessage && !manualSelected"
          role="alert"
          class="break-words text-sm text-n-ruby-11"
        >
          {{ manualMessage }}
        </p>
        <p
          v-if="manualRecorded"
          role="status"
          class="break-words text-sm text-n-teal-11"
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.RECORDED') }}
        </p>
        <p v-if="manualLoading" role="status" class="text-sm text-n-slate-11">
          {{ text('LOADING') }}
        </p>
        <p
          v-else-if="!manualItems.length && !manualError"
          class="text-xs text-n-slate-11"
        >
          {{ t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.EMPTY') }}
        </p>
        <article
          v-for="action in manualItems"
          :key="`${action.origin_id}:${action.rule_code}:${action.destination_kind}`"
          class="min-w-0 rounded-lg border border-n-weak p-3 text-sm"
        >
          <p class="break-words font-semibold">{{ action.rule_code }}</p>
          <p class="break-words text-xs text-n-slate-11">
            {{ operationLabel(action) }}
          </p>
          <button
            type="button"
            :disabled="controlsLocked"
            class="mt-2 max-w-full whitespace-normal rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
            data-review-manual-ending-action
            @click="manual.openManual(action)"
          >
            {{ t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.REVIEW') }}
          </button>
        </article>
        <div class="flex flex-wrap gap-2">
          <button
            v-if="manualMeta && manualMeta.pages > 1"
            type="button"
            :disabled="controlsLocked || manualLoading || manualMeta.page <= 1"
            class="rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-40"
            :aria-label="
              t(
                'JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.PREVIOUS_ACTIONS'
              )
            "
            @click="manual.load(manualMeta.page - 1)"
          >
            {{ text('PREVIOUS') }}
          </button>
          <button
            v-if="manualMeta && manualMeta.pages > 1"
            type="button"
            :disabled="
              controlsLocked ||
              manualLoading ||
              manualMeta.page >= manualMeta.pages
            "
            class="rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-40"
            :aria-label="
              t('JRC_CONTACT_CENTER.ENDING_DESTINATION_REQUESTS.NEXT_ACTIONS')
            "
            @click="manual.load(manualMeta.page + 1)"
          >
            {{ text('NEXT') }}
          </button>
        </div>
      </section>
      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          :disabled="controlsLocked || error === 'DENIED'"
          class="rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-50"
          data-refresh-ending-attempts
          @click="
            history.load(meta?.page || 1);
            manual.load(manualMeta?.page || 1);
          "
        >
          {{ text('REFRESH') }}
        </button>
        <button
          v-if="meta"
          type="button"
          :disabled="controlsLocked || meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-50"
          @click="history.load(meta.page - 1)"
        >
          {{ text('PREVIOUS') }}
        </button>
        <button
          v-if="meta"
          type="button"
          :disabled="controlsLocked || meta.page >= meta.pages"
          class="rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-50"
          @click="history.load(meta.page + 1)"
        >
          {{ text('NEXT') }}
        </button>
      </div>
    </template>
  </section>
</template>
