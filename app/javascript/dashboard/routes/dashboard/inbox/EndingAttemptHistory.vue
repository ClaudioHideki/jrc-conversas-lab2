<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useEndingAttemptHistory } from './useEndingAttemptHistory';
import { usePendingEndingRun } from './usePendingEndingRun';
import PendingEndingReview from './PendingEndingReview.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  qualificationId: { type: [String, Number], required: true },
  authorityKey: { type: String, required: true },
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
  accountId: computed(() => props.accountId),
  qualificationId: computed(() => props.qualificationId),
  authorityKey: computed(() => props.authorityKey),
});
const { opened, items, callSessionId, meta, loading, error } = history;
const pending = usePendingEndingRun({
  accountId: computed(() => props.accountId),
  qualificationId: computed(() => props.qualificationId),
  authorityKey: computed(() => props.authorityKey),
  enabled: opened,
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
const controlsLocked = computed(
  () => loading.value || pendingBusy.value || Boolean(selected.value)
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
const taskRoute = row => ({
  name: 'jrc_projects_detail',
  params: { accountId: props.accountId, projectId: row.target.project_id },
  query: { tab: 'board', taskId: row.target.id },
});
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
      v-if="selected"
      v-model:reviewed="reviewed"
      :operation="selected"
      :busy="pendingBusy"
      :can-submit="canSubmit"
      :message="pendingMessage"
      @confirm="pending.submit()"
      @close="pending.cancel()"
    />
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
          :disabled="pendingBusy"
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
            v-if="row.can_reprocess_pending"
            type="button"
            :disabled="controlsLocked"
            class="max-w-full whitespace-normal rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-2 text-sm text-n-blue-11 disabled:opacity-40"
            data-review-selected-ending-pending
            @click="pending.open(row)"
          >
            {{ pendingLabels.RUN }}
          </button>
          <router-link
            v-if="row.target"
            :to="taskRoute(row)"
            class="inline-flex rounded-lg border border-n-weak px-3 py-2 text-n-blue-11"
            data-ending-attempt-target
          >
            {{ text('OPEN_TASK') }}
          </router-link>
          <p
            v-else-if="row.outcome === 'succeeded'"
            class="text-xs text-n-slate-11"
          >
            {{ text('TARGET_UNAVAILABLE') }}
          </p>
        </article>
      </template>
      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          :disabled="controlsLocked || error === 'DENIED'"
          class="rounded-lg border border-n-weak px-3 py-2 text-xs disabled:opacity-50"
          data-refresh-ending-attempts
          @click="history.load(meta?.page || 1)"
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
