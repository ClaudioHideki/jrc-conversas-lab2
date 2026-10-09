<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { inputClass } from './definitions';
import {
  flowMutationEffects,
  isPlaybookFlowPolicy,
  reviewedFlowEffects,
} from './playbookFlowPolicy';

const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: Boolean,
});
const emit = defineEmits(['update:modelValue', 'validity']);
const { t } = useI18n();
const errors = ref({});
const mutationEffects = flowMutationEffects;
const validPolicy = computed(() => isPlaybookFlowPolicy(props.modelValue));
watch(
  validPolicy,
  valid => {
    if (!valid) {
      errors.value.policy = true;
      emit('validity', false);
    } else if (errors.value.policy) {
      delete errors.value.policy;
      emit('validity', Object.keys(errors.value).length === 0);
    }
  },
  { immediate: true }
);
const phaseThree = computed(
  () => props.modelValue.phase === 3 && props.modelValue.approved_phase === 3
);
const effectLabels = computed(() => ({
  status: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.status'),
  labels: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.labels'),
  assign: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.assign'),
  contact_update: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.contact_update'),
  create_lead: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.create_lead'),
  activity: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.activity'),
  move_deal: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.move_deal'),
  media: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.media'),
  webhook: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.webhook'),
  nico: t('RELATIONSHIP.FLOW_POLICY.EFFECTS.nico'),
}));
const numbers = computed(() => [
  { key: 'phase', label: t('RELATIONSHIP.FLOW_POLICY.PHASE'), min: 1, max: 3 },
  {
    key: 'approved_phase',
    label: t('RELATIONSHIP.FLOW_POLICY.APPROVED_PHASE'),
    min: 0,
    max: 3,
  },
  {
    key: 'approval_ttl_seconds',
    label: t('RELATIONSHIP.FLOW_POLICY.TTL'),
    min: 30,
    max: 900,
  },
  {
    key: 'hourly_limit',
    label: t('RELATIONSHIP.FLOW_POLICY.HOURLY_LIMIT'),
    min: 1,
    max: 1000,
  },
  {
    key: 'max_steps',
    label: t('RELATIONSHIP.FLOW_POLICY.MAX_STEPS'),
    min: 1,
    max: 200,
  },
]);
const pilots = computed(() => [
  { key: 'pilot_company_ids', label: t('RELATIONSHIP.FLOW_POLICY.COMPANIES') },
  {
    key: 'pilot_business_unit_ids',
    label: t('RELATIONSHIP.FLOW_POLICY.UNITS'),
  },
  {
    key: 'pilot_account_user_ids',
    label: t('RELATIONSHIP.FLOW_POLICY.OPERATORS'),
  },
]);
const flags = computed(() => [
  {
    key: 'approval_required',
    label: t('RELATIONSHIP.FLOW_POLICY.APPROVAL_REQUIRED'),
  },
  {
    key: 'allow_unassigned_business_unit',
    label: t('RELATIONSHIP.FLOW_POLICY.UNASSIGNED_UNIT'),
  },
]);
const change = (key, value, valid = true) => {
  const candidate = { ...props.modelValue, [key]: value };
  const accepted = valid && isPlaybookFlowPolicy(candidate);
  if (accepted) delete errors.value[key];
  else errors.value[key] = true;
  emit('validity', Object.keys(errors.value).length === 0);
  if (accepted) emit('update:modelValue', candidate);
};
const changeNumber = (field, text) => {
  const value = Number(text);
  change(
    field.key,
    value,
    text !== '' &&
      Number.isSafeInteger(value) &&
      value >= field.min &&
      value <= field.max
  );
};
const changePilot = (key, text) => {
  const values = text.trim()
    ? text.split(',').map(value => Number(value.trim()))
    : [];
  change(
    key,
    values,
    values.every(value => Number.isSafeInteger(value) && value > 0) &&
      new Set(values).size === values.length
  );
};
const changeEffect = (key, enabled) => {
  const values = reviewedFlowEffects(props.modelValue, key, enabled);
  if (values === null) {
    change('allowed_effects', props.modelValue.allowed_effects, false);
    return;
  }
  change('allowed_effects', values);
};
</script>

<template>
  <fieldset
    class="mt-4 grid gap-3 rounded-lg border border-n-weak p-4"
    :disabled="disabled || !validPolicy"
  >
    <legend class="font-semibold">
      {{ t('RELATIONSHIP.FLOW_POLICY.TITLE') }}
    </legend>
    <p class="text-sm">{{ t('RELATIONSHIP.FLOW_POLICY.GUIDANCE') }}</p>
    <p
      v-if="!validPolicy"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('RELATIONSHIP.FLOW_POLICY.INVALID') }}
    </p>
    <template v-if="validPolicy">
      <div class="grid gap-3 sm:grid-cols-2">
        <label
          v-for="field in numbers"
          :key="field.key"
          class="text-sm"
        >
          {{ field.label }}
          <input
            :value="modelValue[field.key]"
            type="number"
            step="1"
            :min="field.min"
            :max="field.max"
            required
            :class="inputClass"
            :data-testid="`flow-policy-${field.key}`"
            @change="changeNumber(field, $event.target.value)"
          />
        </label>
        <label
          v-for="field in pilots"
          :key="field.key"
          class="text-sm"
        >
          {{ field.label }}
          <input
            :value="modelValue[field.key].join(', ')"
            :class="inputClass"
            :data-testid="`flow-policy-${field.key}`"
            @change="changePilot(field.key, $event.target.value)"
          />
        </label>
      </div>
      <label
        v-for="field in flags"
        :key="field.key"
        class="flex items-center gap-2 text-sm"
      >
        <input
          :checked="modelValue[field.key]"
          type="checkbox"
          :data-testid="`flow-policy-${field.key}`"
          @change="change(field.key, $event.target.checked)"
        />
        {{ field.label }}
      </label>
      <label class="flex items-center gap-2 text-sm">
        <input
          :checked="modelValue.allowed_effects.includes('note')"
          type="checkbox"
          @change="changeEffect('note', $event.target.checked)"
        />
        {{ t('RELATIONSHIP.FLOW_POLICY.NOTE') }}
      </label>
      <label class="flex items-center gap-2 text-sm">
        <input
          :checked="modelValue.allowed_effects.includes('message')"
          type="checkbox"
          @change="changeEffect('message', $event.target.checked)"
        />
        {{ t('RELATIONSHIP.FLOW_POLICY.MESSAGE') }}
      </label>
      <p
        v-if="Object.keys(errors).length"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ t('RELATIONSHIP.FLOW_POLICY.INVALID') }}
      </p>
      <label
        v-for="effect in mutationEffects"
        :key="effect"
        class="flex items-center gap-2 text-sm"
      >
        <input
          type="checkbox"
          :checked="modelValue.allowed_effects.includes(effect)"
          :disabled="
            !phaseThree && !modelValue.allowed_effects.includes(effect)
          "
          :data-testid="`flow-effect-${effect}`"
          @change="changeEffect(effect, $event.target.checked)"
        />
        {{ effectLabels[effect] }}
      </label>
    </template>
  </fieldset>
</template>
