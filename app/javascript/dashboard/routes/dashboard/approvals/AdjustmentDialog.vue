<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { decisionChoices, moneyCents } from './model';
import { minorAmountText } from './tierPresentation';
const props = defineProps({
  request: { type: Object, required: true },
  busy: Boolean,
  error: { type: String, default: '' },
});
const emit = defineEmits(['confirm', 'close']);
const { t } = useI18n();
const dialog = ref(null);
const amount = ref(
  minorAmountText(props.request.adjustment.values.discount_cents)
);
const reason = ref('');
const mode = ref('save');
const selected = ref(0);
const submitted = ref(false);
const requestId = props.request.id;
const expectedVersion = props.request.lock_version;
const choices = computed(() =>
  decisionChoices(props.request).filter(row => row.decision === 'approved')
);
const maximumDiscount = computed(
  () => props.request.adjustment.maximum_discount_cents ?? null
);
const parsed = computed(() => {
  try {
    return moneyCents(amount.value.replace(',', '.'));
  } catch {
    return null;
  }
});
const ready = computed(
  () =>
    !props.busy &&
    !submitted.value &&
    reason.value.trim() &&
    reason.value.length <= 4096 &&
    parsed.value !== null &&
    parsed.value >= 0 &&
    (maximumDiscount.value === null || parsed.value <= maximumDiscount.value) &&
    parsed.value !== props.request.adjustment.values.discount_cents &&
    props.request.id === requestId &&
    props.request.lock_version === expectedVersion &&
    props.request.state === 'pending' &&
    (mode.value === 'save' || choices.value[selected.value])
);
const choiceLabel = (choice, index) => {
  const number =
    props.request.stages.findIndex(row => row.code === choice.step_code) + 1;
  const stage = t('JRC_APPROVALS.stepNumber', { number });
  return choice.principal_name
    ? `${stage} · ${choice.principal_name}`
    : `${stage} · ${index + 1}`;
};
const confirm = () => {
  if (!ready.value) return;
  submitted.value = true;
  const choice =
    mode.value === 'approve' ? choices.value[selected.value] : null;
  emit('confirm', {
    changes: { discount_cents: parsed.value },
    mode: mode.value,
    reason: reason.value.trim(),
    expected_version: expectedVersion,
    ...(choice
      ? {
          step_code: choice.step_code,
          delegation_id: choice.delegation_id,
          ...(choice.own_delegation_id
            ? { own_delegation_id: choice.own_delegation_id }
            : {}),
        }
      : {}),
  });
};
watch([() => props.busy, () => props.error], () => {
  if (!props.busy && props.error) submitted.value = false;
});
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    type="edit"
    contained
    :title="t('JRC_APPROVALS.adjustment.title')"
    :confirm-button-label="t(`JRC_APPROVALS.adjustment.${mode}`)"
    :cancel-button-label="t('JRC_APPROVALS.cancel')"
    :disable-confirm-button="!ready"
    :is-loading="busy || submitted"
    :dismissible="!busy && !submitted"
    @confirm="confirm"
    @close="emit('close')"
  >
    <section class="min-w-0 space-y-4">
      <p class="break-words font-medium">
        {{ request.policy_name }} · #{{ request.id }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_APPROVALS.adjustment.notice') }}
      </p>
      <div class="grid min-w-0 gap-4 md:grid-cols-2">
        <section
          class="min-w-0 space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        >
          <p class="text-sm">
            {{ t('JRC_APPROVALS.adjustment.original') }}:
            {{ minorAmountText(request.adjustment.values.discount_cents) }}
            {{ request.adjustment.currency }}
          </p>
          <p
            v-if="maximumDiscount !== null"
            class="text-sm"
          >
            {{
              t('JRC_APPROVALS.adjustment.maximum', {
                value: minorAmountText(maximumDiscount),
                currency: request.adjustment.currency,
              })
            }}
          </p>
          <p
            v-if="parsed !== null && parsed >= 0"
            class="break-words rounded-lg bg-n-teal-3 p-3 text-sm text-n-teal-11"
          >
            {{ t('JRC_APPROVALS.adjustment.summary') }}:
            {{
              t('JRC_APPROVALS.adjustment.values', {
                before: minorAmountText(
                  request.adjustment.values.discount_cents
                ),
                after: minorAmountText(parsed),
                currency: request.adjustment.currency,
              })
            }}
          </p>
        </section>
        <section
          class="min-w-0 rounded-xl border border-n-weak bg-n-solid-2 p-4"
        >
          <label class="block text-sm font-medium"
            >{{ t('JRC_APPROVALS.adjustment.discount') }}
            <input
              v-model="amount"
              inputmode="decimal"
              :disabled="busy || submitted"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3"
            />
          </label>
          <p
            v-if="maximumDiscount !== null && parsed > maximumDiscount"
            data-testid="adjustment-over-maximum"
            role="alert"
            class="text-sm text-n-ruby-11"
          >
            {{ t('JRC_APPROVALS.adjustment.overMaximum') }}
          </p>
          <p
            v-if="parsed === null"
            role="alert"
            class="text-sm text-n-ruby-11"
          >
            {{ t('JRC_APPROVALS.typedError') }}
          </p>
          <label class="block text-sm font-medium"
            >{{ t('JRC_APPROVALS.reason') }}
            <textarea
              v-model="reason"
              rows="6"
              maxlength="4096"
              :disabled="busy || submitted"
              required
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3"
            />
          </label>
        </section>
      </div>
      <label class="block text-sm font-medium"
        >{{ t('JRC_APPROVALS.adjustment.action') }}
        <select
          v-model="mode"
          :disabled="busy || submitted"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3"
        >
          <option value="save">{{ t('JRC_APPROVALS.adjustment.save') }}</option>
          <option
            v-if="choices.length"
            value="approve"
          >
            {{ t('JRC_APPROVALS.adjustment.approve') }}
          </option>
        </select>
      </label>
      <label
        v-if="mode === 'approve'"
        class="block text-sm font-medium"
        >{{ t('JRC_APPROVALS.steps') }}
        <select
          v-model="selected"
          :disabled="busy || submitted"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3"
        >
          <option
            v-for="(choice, index) in choices"
            :key="index"
            :value="index"
          >
            {{ choiceLabel(choice, index) }}
          </option>
        </select>
      </label>
      <p
        v-if="error"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ error }}
      </p>
    </section>
  </Dialog>
</template>
