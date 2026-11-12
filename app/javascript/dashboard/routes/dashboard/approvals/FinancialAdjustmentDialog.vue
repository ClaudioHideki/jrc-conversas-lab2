<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { decisionChoices } from './model';
import {
  financialChangeSet,
  ADJUSTABLE_TYPES,
} from './approvedAdjustmentState';
const props = defineProps({
  request: { type: Object, required: true },
  busy: Boolean,
  error: { type: String, default: '' },
  errorState: { type: Object, default: null },
});
const emit = defineEmits(['close', 'confirm']);
const { t } = useI18n();
const dialog = ref(null);
const draft = ref(JSON.parse(JSON.stringify(props.request.adjustment.values)));
const reason = ref('');
const mode = ref('save');
const selected = ref(0);
const submitted = ref(false);
const denied = ref(false);
const captured = JSON.stringify([
  props.request.id,
  props.request.lock_version,
  props.request.adjustment,
]);
const current = computed(
  () =>
    !denied.value &&
    props.request.state === 'pending' &&
    JSON.stringify([
      props.request.id,
      props.request.lock_version,
      props.request.adjustment,
    ]) === captured
);
const fields = computed(() =>
  denied.value ? {} : props.request.adjustment.fields || {}
);
const changes = computed(() => {
  try {
    return financialChangeSet(
      props.request.adjustment.values,
      draft.value,
      fields.value
    );
  } catch {
    return null;
  }
});
const choices = computed(() =>
  decisionChoices(props.request).filter(v => v.decision === 'approved')
);
const ready = computed(
  () =>
    current.value &&
    !props.busy &&
    !submitted.value &&
    reason.value.trim() &&
    reason.value.length <= 4000 &&
    changes.value &&
    Object.keys(changes.value).length &&
    (mode.value === 'save' || choices.value[selected.value])
);
const confirm = () => {
  if (!ready.value) return;
  submitted.value = true;
  const choice =
    mode.value === 'approve' ? choices.value[selected.value] : null;
  emit('confirm', {
    changes: changes.value,
    reason: reason.value.trim(),
    mode: mode.value,
    expected_version: props.request.lock_version,
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
watch(
  () => props.errorState,
  value => {
    if ([401, 403, 404].includes(value?.status)) {
      denied.value = true;
      draft.value = {};
      reason.value = '';
      emit('close');
    }
    if (!props.busy && [400, 401, 403, 404, 409, 422].includes(value?.status))
      submitted.value = false;
  }
);
onMounted(() => dialog.value.open());
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    :title="t('JRC_APPROVALS.approvedTerms.title')"
    :disable-confirm-button="!ready"
    :is-loading="busy || submitted"
    :dismissible="!busy && !submitted"
    @confirm="confirm"
    @close="emit('close')"
  >
    <p>{{ t('JRC_APPROVALS.approvedTerms.notice') }}</p>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <fieldset
      :disabled="busy || submitted || !current"
      class="space-y-3"
    >
      <label
        v-for="(rule, key) in fields"
        :key="key"
        class="block"
        >{{ t(`JRC_APPROVALS.approvedTerms.fields.${key}`) }}
        <span class="text-sm"
          >({{ request.adjustment.values[key] ?? '—' }})</span
        >
        <select
          v-if="ADJUSTABLE_TYPES[key] === 'choice'"
          v-model="draft[key]"
          class="w-full rounded border p-2"
        >
          <option
            v-for="value in rule.options"
            :key="value"
            :value="value"
          >
            {{ value }}
          </option>
        </select>
        <input
          v-else-if="ADJUSTABLE_TYPES[key] === 'integer'"
          v-model="draft[key]"
          type="number"
          :min="rule.min"
          :max="rule.max"
          step="1"
          class="w-full rounded border p-2" />
        <input
          v-else-if="ADJUSTABLE_TYPES[key] === 'date'"
          v-model="draft[key]"
          type="date"
          class="w-full rounded border p-2"
      /></label>
      <label class="block"
        >{{ t('JRC_APPROVALS.reason')
        }}<textarea
          v-model="reason"
          maxlength="4000"
          required
          class="w-full rounded border p-2"
        />
      </label>
      <label
        ><select v-model="mode">
          <option value="save">{{ t('JRC_APPROVALS.adjustment.save') }}</option>
          <option value="approve">
            {{ t('JRC_APPROVALS.adjustment.approve') }}
          </option>
        </select></label
      >
      <select
        v-if="mode === 'approve'"
        v-model.number="selected"
      >
        <option
          v-for="(choice, index) in choices"
          :key="index"
          :value="index"
        >
          {{ t('JRC_APPROVALS.stepNumber', { number: index + 1 }) }}
          {{ choice.principal_name || '' }}
        </option>
      </select>
    </fieldset>
    <p
      v-if="changes === null"
      role="alert"
    >
      {{ t('JRC_APPROVALS.approvedTerms.invalid') }}
    </p>
    <p>{{ t('JRC_APPROVALS.approvedTerms.escalation') }}</p>
  </Dialog>
</template>
