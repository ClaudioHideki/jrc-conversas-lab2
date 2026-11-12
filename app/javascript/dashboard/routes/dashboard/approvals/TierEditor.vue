<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import TierBound from './TierBound.vue';
import TierSummary from './TierSummary.vue';
import { copy } from './model';
import { approvalStageLabel, minorAmountFields } from './tierPresentation';
const props = defineProps({
  modelValue: { type: Object, required: true },
  fields: { type: Object, required: true },
  steps: { type: Array, required: true },
  options: { type: Object, required: true },
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();
const numericFields = computed(() =>
  Object.keys(props.fields).filter(field =>
    ['integer', 'decimal', 'money'].includes(props.fields[field])
  )
);
const type = computed(() => props.fields[props.modelValue.field]);
const presentationType = computed(() =>
  type.value === 'integer' && minorAmountFields.includes(props.modelValue.field)
    ? 'minor_money'
    : type.value
);
const fieldLabel = name =>
  minorAmountFields.includes(name)
    ? t(`JRC_APPROVALS.tiers.moneyLabels.${name}`)
    : t(`JRC_APPROVALS.catalogFields.${name}`);
const patch = values =>
  emit('update:modelValue', { ...copy(props.modelValue), ...values });
const rowPatch = (index, values) => {
  const rows = copy(props.modelValue.rows);
  rows[index] = { ...rows[index], ...values };
  patch({ rows });
};
const field = selected => {
  if (selected === props.modelValue.field) return;
  // A type change needs new typed bounds; retain the rows and their approvers.
  patch({
    field: selected,
    currency: props.fields[selected] === 'money' ? '' : null,
    min: null,
    max: null,
    rows: props.modelValue.rows.map(row => ({
      ...row,
      min: null,
      max: null,
      min_inclusive: false,
      max_inclusive: false,
    })),
  });
};
const add = () => {
  if (props.modelValue.rows.length >= 16) return;
  const previous = props.modelValue.rows.at(-1);
  const lower = previous ? previous.max : props.modelValue.min;
  patch({
    rows: [
      ...copy(props.modelValue.rows),
      {
        min: copy(lower),
        max: null,
        min_inclusive: lower !== null && (!previous || !previous.max_inclusive),
        max_inclusive: false,
        step_codes: [],
      },
    ],
  });
};
const toggle = (index, code) => {
  const row = props.modelValue.rows[index];
  const selected = row.step_codes.includes(code)
    ? row.step_codes.filter(value => value !== code)
    : [...row.step_codes, code];
  rowPatch(index, {
    step_codes: props.steps
      .filter(step => selected.includes(step.code))
      .map(step => step.code),
  });
};
</script>

<template>
  <section
    class="grid min-w-0 gap-4 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)]"
  >
    <div class="min-w-0 space-y-4">
      <div
        class="grid gap-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-4 sm:grid-cols-2"
      >
        <label class="min-w-0 text-sm"
          >{{ t('JRC_APPROVALS.tiers.field') }}
          <select
            :value="modelValue.field"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            @change="field($event.target.value)"
          >
            <option value="">{{ t('JRC_APPROVALS.select') }}</option>
            <option
              v-for="name in numericFields"
              :key="name"
              :value="name"
            >
              {{ fieldLabel(name) }}
            </option>
          </select>
        </label>
        <label class="text-sm"
          >{{ t('JRC_APPROVALS.tiers.coverage') }}
          <select
            :value="modelValue.coverage"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            @change="patch({ coverage: $event.target.value })"
          >
            <option value="complete">
              {{ t('JRC_APPROVALS.tiers.complete') }}
            </option>
            <option value="partial">
              {{ t('JRC_APPROVALS.tiers.partial') }}
            </option>
          </select>
        </label>
        <label
          v-if="type === 'money'"
          class="text-sm"
          >{{ t('JRC_APPROVALS.currency') }}
          <input
            :value="modelValue.currency"
            maxlength="3"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
            @change="patch({ currency: $event.target.value })"
          />
        </label>
        <template v-if="type">
          <TierBound
            :model-value="modelValue.min"
            :type="presentationType"
            :label="t('JRC_APPROVALS.tiers.domainMin')"
            @change="patch({ min: $event.value })"
          />
          <TierBound
            :model-value="modelValue.max"
            :type="presentationType"
            :label="t('JRC_APPROVALS.tiers.domainMax')"
            @change="patch({ max: $event.value })"
          />
        </template>
        <p class="text-sm text-n-slate-11 sm:col-span-2">
          {{ t('JRC_APPROVALS.tiers.domainHelp') }}
        </p>
      </div>
      <article
        v-for="(row, index) in modelValue.rows"
        :key="index"
        class="min-w-0 space-y-3 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h4 class="font-semibold">
            {{ t('JRC_APPROVALS.tiers.rangeNumber', { number: index + 1 }) }}
          </h4>
          <Button
            variant="faded"
            :label="t('JRC_APPROVALS.remove')"
            @click="
              patch({
                rows: modelValue.rows.filter(
                  (_, position) => position !== index
                ),
              })
            "
          />
        </div>
        <div
          v-if="type"
          class="grid min-w-0 gap-3 sm:grid-cols-2"
        >
          <TierBound
            :model-value="row.min"
            :included="row.min_inclusive"
            :type="presentationType"
            :label="t('JRC_APPROVALS.tiers.from')"
            @change="
              rowPatch(index, {
                min: $event.value,
                min_inclusive: $event.included,
              })
            "
          />
          <TierBound
            :model-value="row.max"
            :included="row.max_inclusive"
            :type="presentationType"
            :label="t('JRC_APPROVALS.tiers.to')"
            @change="
              rowPatch(index, {
                max: $event.value,
                max_inclusive: $event.included,
              })
            "
          />
        </div>
        <fieldset class="flex min-w-0 flex-wrap gap-3">
          <legend class="mb-2 text-sm font-medium">
            {{ t('JRC_APPROVALS.tiers.selectStages') }}
          </legend>
          <label
            v-for="(step, stepIndex) in steps"
            :key="step.code"
            class="flex min-w-0 max-w-full items-start gap-2 text-sm"
          >
            <input
              type="checkbox"
              :checked="row.step_codes.includes(step.code)"
              @change="toggle(index, step.code)"
            />
            <span class="min-w-0 break-words"
              >{{ t('JRC_APPROVALS.stepNumber', { number: stepIndex + 1 }) }} ·
              {{
                approvalStageLabel(
                  step,
                  options,
                  t('JRC_APPROVALS.tiers.selectStages')
                )
              }}
            </span>
          </label>
        </fieldset>
      </article>
      <Button
        :label="t('JRC_APPROVALS.tiers.add')"
        :disabled="!type || modelValue.rows.length >= 16"
        variant="faded"
        @click="add"
      />
      <p
        v-if="presentationType === 'minor_money'"
        class="text-sm text-n-slate-11"
      >
        {{ t('JRC_APPROVALS.tiers.sourceCurrency') }}
      </p>
      <p class="rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11">
        {{ t('JRC_APPROVALS.tiers.howItWorks') }}
      </p>
    </div>
    <TierSummary
      :tiers="modelValue"
      :steps="steps"
      :options="options"
    />
  </section>
</template>
