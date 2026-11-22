<script setup>
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/jrcContactCenter';
import { verifiedPauseApprovalPreview } from '../helpers/pauseApprovalPreview';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  memberId: { type: [String, Number], required: true },
  contextKey: { type: String, required: true },
  mode: { type: String, default: 'request' },
  stateVersion: { type: String, required: true },
  requestRevision: { type: String, required: true },
  reasonCode: { type: String, default: '' },
  reasonLabel: { type: String, default: '' },
  queueId: { type: [String, Number], default: '' },
  justification: { type: String, default: '' },
  requestId: { type: String, default: '' },
  approvalRequired: { type: Boolean, default: false },
});
const emit = defineEmits(['updated', 'close', 'refresh', 'denied']);
const { t } = useI18n();
const dialog = ref(null);
const state = reactive({
  busy: false,
  uncertain: false,
  error: false,
  denied: false,
  code: '',
  confirmClose: false,
  previewFailed: false,
});
const approvalPreview = ref(null);
const confirmLabel = computed(() => {
  if (props.mode === 'apply')
    return t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.APPLY');
  if (props.approvalRequired && props.mode === 'request' && !state.uncertain)
    return t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.REQUEST_CONFIRM');
  if (state.uncertain) return t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.RETRY');
  return props.mode === 'cancel'
    ? t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CONFIRM_CANCEL')
    : t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CONFIRM');
});
const errorLabels = computed(() => ({
  pause_approval_review_required: t(
    'JRC_CONTACT_CENTER.PAUSE_APPROVAL.REVIEW_REQUIRED'
  ),
  pause_approval_required: t(
    'JRC_CONTACT_CENTER.PAUSE_APPROVAL.APPROVAL_REQUIRED'
  ),
  pause_approval_policy_missing: t(
    'JRC_CONTACT_CENTER.PAUSE_APPROVAL.POLICY_MISSING'
  ),
  pause_approval_unavailable: t(
    'JRC_CONTACT_CENTER.PAUSE_APPROVAL.UNAVAILABLE'
  ),
  stale_pause_request: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CONTEXT_CHANGED'),
  state_conflict: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CONTEXT_CHANGED'),
  pause_already_applied: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.ALREADY_APPLIED'),
  pause_request_cancelled: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CANCELLED'),
  pause_request_review_required: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.BLOCKED'),
}));
const dialogTitle = computed(() => {
  if (props.mode === 'apply')
    return t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.APPLY');
  if (props.approvalRequired && props.mode === 'request')
    return t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.REVIEW_TITLE');
  return props.mode === 'cancel'
    ? t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CANCEL_TITLE')
    : t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.TITLE');
});
const labels = computed(() => ({
  title: dialogTitle.value,
  hint: t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.HINT'),
  close: state.confirmClose
    ? t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CONFIRM_CLOSE')
    : t('JRC_CONTACT_CENTER.LOCAL_IVR.CLOSE'),
  confirm: confirmLabel.value,
  failed:
    errorLabels.value[state.code] ||
    t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.FAILED'),
}));
const review = ref({
  reason: props.reasonLabel,
  justification: props.justification,
});
const context = {
  account: String(props.accountId),
  member: String(props.memberId),
  mode: props.mode,
  requestId: props.requestId,
  token: props.contextKey,
  approvalRequired: props.approvalRequired,
};
const values = {
  expected_state_version: props.stateVersion,
  expected_request_revision: props.requestRevision,
  reason_code: props.reasonCode,
  ...(props.queueId ? { queue_id: String(props.queueId) } : {}),
  ...(props.justification.trim()
    ? { justification: props.justification.trim() }
    : {}),
};
let attempt = null;
let alive = true;
const sameContext = () =>
  alive &&
  context.account === String(props.accountId) &&
  context.member === String(props.memberId) &&
  context.mode === props.mode &&
  context.requestId === props.requestId &&
  context.token === props.contextKey &&
  context.approvalRequired === props.approvalRequired;
const validReceipt = data =>
  String(data?.account_id) === context.account &&
  String(data?.item?.account_user_id) === context.member &&
  typeof data?.item?.state_version === 'string' &&
  typeof data?.item?.pause_request_revision === 'string' &&
  /^[0-9a-f]{64}$/.test(data.item.pause_request_revision) &&
  data?.receipt?.request_id ===
    (context.mode === 'request' ? attempt.command_id : context.requestId) &&
  (context.mode === 'cancel'
    ? data?.receipt?.state === 'cancelled'
    : ['pending', 'blocked', 'applied', 'cancelled'].includes(
        data?.receipt?.state
      ));

const loadApprovalPreview = async () => {
  if (
    !sameContext() ||
    state.busy ||
    !props.approvalRequired ||
    context.mode !== 'request'
  )
    return;
  state.busy = true;
  state.previewFailed = false;
  approvalPreview.value = null;
  if (!attempt)
    attempt = Object.freeze({ ...values, command_id: crypto.randomUUID() });
  try {
    const response = await API.previewPauseApproval(context.account, attempt);
    if (!sameContext()) return;
    const verified = verifiedPauseApprovalPreview(
      response.data,
      context,
      attempt
    );
    if (!verified) throw new Error('Invalid all-scope pause approval preview');
    approvalPreview.value = verified;
  } catch (error) {
    if (!sameContext()) return;
    state.previewFailed = true;
    if ([401, 403].includes(error.response?.status)) {
      state.denied = true;
      review.value = {};
      attempt = null;
      emit('denied', context.token);
    }
  } finally {
    if (sameContext()) state.busy = false;
  }
};

const send = () => {
  if (context.mode === 'cancel')
    return API.cancelDeferredPause(context.account, context.requestId);
  if (context.mode === 'apply')
    return API.applyApprovedPause(
      context.account,
      context.requestId,
      values.expected_state_version
    );
  if (props.approvalRequired)
    return API.requestDeferredPause(
      context.account,
      attempt,
      approvalPreview.value.digest
    );
  return API.requestDeferredPause(context.account, attempt);
};

const submit = async () => {
  if (
    state.busy ||
    state.denied ||
    !sameContext() ||
    (state.error && !state.uncertain) ||
    (context.mode === 'request' &&
      props.approvalRequired &&
      !approvalPreview.value)
  )
    return;
  state.busy = true;
  state.error = false;
  state.confirmClose = false;
  if (context.mode === 'request' && !attempt)
    attempt = Object.freeze({ ...values, command_id: crypto.randomUUID() });
  try {
    const response = await send();
    if (!sameContext()) return;
    if (!validReceipt(response.data))
      throw new Error('Unverified deferred pause receipt');
    state.uncertain = false;
    if (response.data.receipt.private_details_available === false)
      review.value = {};
    emit('updated', response.data.item, context.token);
    if (
      context.mode !== 'cancel' &&
      ['blocked', 'cancelled'].includes(response.data.receipt.state)
    ) {
      state.error = true;
      state.code =
        response.data.receipt.state === 'blocked'
          ? 'pause_request_review_required'
          : 'pause_request_cancelled';
      return;
    }
    dialog.value.close();
  } catch (error) {
    if (!sameContext()) return;
    const status = error.response?.status;
    if ([401, 403].includes(status)) {
      state.denied = true;
      state.uncertain = false;
      review.value = {};
      attempt = null;
      emit('denied', context.token);
      return;
    }
    state.code = error.response?.data?.error || '';
    state.error = true;
    state.uncertain = ![400, 404, 409, 422].includes(status);
  } finally {
    if (sameContext()) state.busy = false;
  }
};
const close = () => {
  if (state.busy) return;
  if (state.uncertain && !state.confirmClose) {
    state.confirmClose = true;
    return;
  }
  if (state.uncertain || state.error) emit('refresh', context.token);
  dialog.value.close();
};
const beforeUnload = event => {
  if (!state.busy && !state.uncertain) return;
  event.preventDefault();
  event.returnValue = '';
};
watch(
  () => [
    props.accountId,
    props.memberId,
    props.mode,
    props.requestId,
    props.contextKey,
    props.approvalRequired,
  ],
  () => {
    alive = false;
    approvalPreview.value = null;
    attempt = null;
    review.value = {};
    emit('close', context.token);
  }
);
onMounted(() => {
  dialog.value.open();
  loadApprovalPreview();
  window.addEventListener('beforeunload', beforeUnload);
});
onBeforeUnmount(() => {
  alive = false;
  approvalPreview.value = null;
  attempt = null;
  values.justification = '';
  window.removeEventListener('beforeunload', beforeUnload);
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="labels.title"
    :description="labels.hint"
    contained
    :use-form="false"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :dismissible="!state.busy && !state.uncertain"
    :close-on-click-outside="false"
    @close="emit('close', context.token)"
  >
    <div
      class="max-h-[60vh] min-w-0 space-y-4 overflow-y-auto text-sm text-n-slate-12"
      data-deferred-pause-dialog
    >
      <p class="break-words">{{ review.reason }}</p>
      <p v-if="review.justification" class="whitespace-pre-wrap break-words">
        {{ review.justification }}
      </p>
      <div
        v-if="approvalRequired && mode === 'request'"
        class="space-y-3"
        data-pause-approval-review
      >
        <p>{{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.ALL_AFFECTED') }}</p>
        <p>{{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.NO_EARLY_PAUSE') }}</p>
        <div
          v-for="scope in approvalPreview?.scopes || []"
          :key="`${scope.company}:${scope.business}`"
          class="min-w-0 rounded-lg border border-n-weak p-3"
        >
          <p>
            {{
              t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.SCOPE', {
                company: scope.company,
                unit: scope.business || '—',
              })
            }}
          </p>
          <p v-for="unit in scope.units" :key="unit.id" class="break-words">
            {{ unit.name }}
          </p>
        </div>
        <p v-if="state.previewFailed" role="alert">
          {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.PREVIEW_FAILED') }}
        </p>
        <Button
          v-if="state.previewFailed && !state.denied"
          type="button"
          :disabled="state.busy"
          :label="t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.RETRY_PREVIEW')"
          data-pause-approval-preview-retry
          @click="loadApprovalPreview"
        />
      </div>
      <p v-if="mode === 'apply'">
        {{ t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.APPLY_REVIEW') }}
      </p>
      <p v-if="mode === 'cancel'">
        {{ t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CANCEL_HINT') }}
      </p>
      <p
        v-if="state.denied"
        role="alert"
        class="rounded-lg bg-n-ruby-2 p-3 text-n-ruby-11"
      >
        {{ t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.DENIED') }}
      </p>
      <p
        v-if="state.uncertain"
        role="alert"
        class="rounded-lg bg-n-amber-2 p-3 text-n-amber-11"
        data-deferred-pause-uncertain
      >
        {{ t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.UNCERTAIN') }}
      </p>
      <p
        v-else-if="state.error"
        role="alert"
        class="rounded-lg bg-n-ruby-2 p-3 text-n-ruby-11"
      >
        {{ labels.failed }}
      </p>
      <p
        v-if="state.confirmClose"
        role="alert"
        class="rounded-lg border border-n-amber-6 p-3"
        data-deferred-pause-close-review
      >
        {{ t('JRC_CONTACT_CENTER.DEFERRED_PAUSE.CLOSE_REVIEW') }}
      </p>
    </div>
    <template #footer>
      <div class="flex w-full flex-wrap justify-end gap-2">
        <Button
          type="button"
          faded
          slate
          :disabled="state.busy"
          :label="labels.close"
          data-deferred-pause-close
          @click="close"
        />
        <Button
          v-if="!state.denied && (!state.error || state.uncertain)"
          type="button"
          :disabled="
            state.busy ||
            (mode === 'request' && approvalRequired && !approvalPreview)
          "
          :is-loading="state.busy"
          :label="labels.confirm"
          data-deferred-pause-confirm
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
