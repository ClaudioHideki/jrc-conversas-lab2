<script setup>
/* global BigInt */
import { useI18n } from 'vue-i18n';
import {
  approvalStageLabel,
  minorAmountFields,
  minorAmountText,
} from './tierPresentation';
const props = defineProps({
  tiers: { type: Object, required: true },
  steps: { type: Array, required: true },
  options: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const value = bound => {
  if (bound === null) return t('JRC_APPROVALS.tiers.unbounded');
  if (bound && typeof bound === 'object') {
    if (!Number.isSafeInteger(bound.amount_cents)) return '—';
    const cents = BigInt(bound.amount_cents);
    const absolute = cents < 0n ? -cents : cents;
    return `${cents < 0n ? '-' : ''}${absolute / 100n}.${String(absolute % 100n).padStart(2, '0')} ${bound.currency}`;
  }
  if (
    minorAmountFields.includes(props.tiers.field) &&
    typeof bound === 'number'
  )
    return minorAmountText(bound);
  return bound === '' ? '—' : String(bound);
};
const approvers = code => {
  const index = props.steps.findIndex(step => step.code === code);
  if (index < 0) return t('JRC_APPROVALS.tiers.selectStages');
  return approvalStageLabel(
    props.steps[index],
    props.options,
    t('JRC_APPROVALS.stepNumber', { number: index + 1 })
  );
};
</script>

<template>
  <aside
    class="min-w-0 space-y-3 rounded-xl border border-n-teal-6 bg-n-teal-2 p-4 text-sm text-n-slate-12"
  >
    <h3 class="font-semibold">{{ t('JRC_APPROVALS.tiers.summary') }}</h3>
    <p v-if="tiers.field">
      {{
        minorAmountFields.includes(tiers.field)
          ? t(`JRC_APPROVALS.tiers.moneyLabels.${tiers.field}`)
          : t(`JRC_APPROVALS.catalogFields.${tiers.field}`)
      }}
    </p>
    <ol class="space-y-3">
      <li
        v-for="(row, index) in tiers.rows"
        :key="index"
        class="space-y-1 rounded-lg bg-n-solid-2 p-3"
      >
        <p class="break-words font-medium">
          {{ row.min_inclusive ? '≥' : '>' }} {{ value(row.min) }} ·
          {{ row.max_inclusive ? '≤' : '<' }} {{ value(row.max) }}
        </p>
        <p>
          {{
            row.step_codes.map(approvers).join(' → ') ||
            t('JRC_APPROVALS.tiers.selectStages')
          }}
        </p>
      </li>
    </ol>
    <p class="text-n-slate-11">
      {{ t('JRC_APPROVALS.tiers.serverValidation') }}
    </p>
  </aside>
</template>
