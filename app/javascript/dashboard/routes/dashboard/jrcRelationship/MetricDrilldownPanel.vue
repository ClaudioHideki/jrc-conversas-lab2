<script setup>
import { useI18n } from 'vue-i18n';
import {
  buttonClass,
  date as formatDate,
  money as formatMoney,
} from './definitions';
const props = defineProps({
  data: { type: Object, required: true },
  metadata: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close', 'page']);
const { t } = useI18n();
const date = value => formatDate(value, props.metadata.formatting);
const money = value => formatMoney(value, props.metadata.formatting);
</script>

<template>
  <section
    class="space-y-3 rounded-xl border border-n-weak p-4"
    data-testid="metric-drilldown"
  >
    <div class="flex justify-between">
      <h3 class="font-semibold">
        {{ t(`RELATIONSHIP.METRICS.${data.metric}`) }} ·
        {{ data.metric.endsWith('_cents') ? money(data.value) : data.value }}
      </h3>
      <button
        :class="buttonClass"
        @click="emit('close')"
      >
        {{ t('RELATIONSHIP.CLOSE') }}
      </button>
    </div>
    <p class="text-sm">
      {{ t('RELATIONSHIP.DRILLDOWN_SOURCE_COUNT', { count: data.total }) }} ·
      {{ t(`RELATIONSHIP.AGGREGATIONS.${data.aggregation}`) }}
    </p>
    <p
      v-if="data.day"
      class="text-sm"
    >
      {{ date(data.day) }}
    </p>
    <p
      v-if="data.calculation"
      class="text-sm"
    >
      {{
        data.metric === 'nps'
          ? `100 × (${data.calculation.promoters} − ${data.calculation.detractors}) / ${data.calculation.denominator}`
          : data.calculation.formula === 'average'
            ? t('RELATIONSHIP.AVERAGE_DENOMINATOR', {
                count: data.calculation.denominator,
              })
            : `100 × ${data.calculation.numerator} / ${data.calculation.denominator}`
      }}
    </p>
    <div class="overflow-x-auto">
      <table class="w-full text-left text-sm">
        <thead>
          <tr>
            <th
              v-for="key in ['customer', 'origin', 'status', 'due_at', 'value']"
              :key="key"
              class="p-2"
            >
              {{ t(`RELATIONSHIP.FIELDS.${key}`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in data.payload"
            :key="`${row.source_type}:${row.id}`"
            class="border-t border-n-weak"
          >
            <td class="p-2">{{ row.customer || row.label }}</td>
            <td class="p-2">
              <RouterLink
                v-if="row.route"
                :to="row.route"
                class="text-n-brand"
              >
                {{ row.label }} #{{ row.id }} </RouterLink
              ><span v-else>{{ row.label }} #{{ row.id }}</span>
              <p class="text-xs text-n-slate-11">
                {{ t(`RELATIONSHIP.SOURCES.${row.source_kind}`) }}
              </p>
            </td>
            <td class="p-2">
              {{ row.status ? t(`RELATIONSHIP.STATES.${row.status}`) : '—' }}
            </td>
            <td class="p-2">{{ date(row.date) }}</td>
            <td class="p-2">
              {{
                row.amount_cents !== undefined
                  ? money(row.amount_cents)
                  : (row.score ?? row.elapsed_minutes ?? '—')
              }}
              <p
                v-if="row.comment"
                class="mt-1 text-xs"
              >
                {{ row.comment }}
              </p>
              <p v-if="data.aggregation === 'cohort'">
                {{ t('RELATIONSHIP.ARROW') }} {{ money(row.closing_cents) }}
              </p>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p
      v-if="!data.payload.length"
      class="text-sm text-n-slate-11"
    >
      {{ t('RELATIONSHIP.EMPTY') }}
    </p>
    <div class="flex justify-between">
      <button
        :class="buttonClass"
        :disabled="data.page <= 1"
        @click="emit('page', data.page - 1)"
      >
        {{ t('RELATIONSHIP.PREVIOUS') }}</button
      ><button
        :class="buttonClass"
        :disabled="data.page * data.per_page >= data.total"
        @click="emit('page', data.page + 1)"
      >
        {{ t('RELATIONSHIP.NEXT') }}
      </button>
    </div>
  </section>
</template>
