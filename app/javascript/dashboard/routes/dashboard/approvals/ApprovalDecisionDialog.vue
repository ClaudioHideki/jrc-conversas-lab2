<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { scopeLabel } from './model';
const props = defineProps({
  request: { type: Object, required: true },
  choice: { type: Object, required: true },
  context: { type: Object, default: null },
  reason: { type: String, required: true },
  busy: Boolean,
  error: { type: String, default: '' },
  errorState: { type: Object, default: null },
});
const emit = defineEmits(['confirm', 'close']);
const { t } = useI18n();
const dialog = ref(null);
const submitted = ref(false);
const expectedVersion = props.request.lock_version;
const requestId = props.request.id;
const decision = props.choice.decision;
const ready = computed(
  () =>
    !props.busy &&
    !submitted.value &&
    !!props.reason.trim() &&
    props.request.id === requestId &&
    props.request.lock_version === expectedVersion &&
    props.request.state === 'pending'
);
const confirm = () => {
  if (!ready.value) return;
  submitted.value = true;
  emit('confirm', {
    step_code: props.choice.step_code,
    decision,
    delegation_id: props.choice.delegation_id,
    ...(props.choice.own_delegation_id
      ? { own_delegation_id: props.choice.own_delegation_id }
      : {}),
    reason: props.reason.trim(),
    expected_version: expectedVersion,
  });
};
watch([() => props.busy, () => props.errorState], () => {
  if (!props.busy) submitted.value = false;
});
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    width="lg"
    :title="t('JRC_APPROVALS.confirmDecision')"
    :confirm-button-label="t(`JRC_APPROVALS.decisionLabels.${choice.decision}`)"
    :cancel-button-label="t('JRC_APPROVALS.cancel')"
    :disable-confirm-button="!ready"
    :is-loading="busy || submitted"
    :dismissible="!busy && !submitted"
    @confirm="confirm"
    @close="emit('close')"
  >
    <section class="min-w-0 space-y-4">
      <p class="font-semibold">
        {{ t('JRC_APPROVALS.request') }} #{{ request.id }} ·
        {{ t(`JRC_APPROVALS.decisionLabels.${choice.decision}`) }}
      </p>
      <p class="break-words text-sm">
        {{ scopeLabel(context, request) || t('JRC_APPROVALS.groupScope') }}
      </p>
      <p class="break-words text-sm">{{ request.policy_name }}</p>
      <p
        v-if="choice.delegation_id || choice.own_delegation_id"
        class="text-sm"
      >
        {{
          choice.principal_name
            ? t('JRC_APPROVALS.onBehalfOf', { name: choice.principal_name })
            : t('JRC_APPROVALS.delegatedDecision')
        }}
      </p>
      <div
        class="max-h-56 overflow-y-auto whitespace-pre-wrap break-words rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm"
      >
        {{ reason }}
      </div>
      <slot name="origin" />
      <p
        v-if="error"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_APPROVALS.confirmDecisionNotice') }}
      </p>
    </section>
  </Dialog>
</template>
