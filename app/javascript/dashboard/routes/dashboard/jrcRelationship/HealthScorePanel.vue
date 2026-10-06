<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { buttonClass, date as formatDate } from './definitions';
const props = defineProps({
  metrics: { type: Object, default: () => ({}) },
  rows: { type: Array, default: () => [] },
  metadata: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['open', 'filter', 'inspect']);
const { t } = useI18n();
const bands = ['healthy', 'attention', 'risk', 'critical'];
const trend = computed(() => props.metrics.health_trend || []);
const points = computed(() =>
  trend.value
    .map((point, index) =>
      point.score === null
        ? ''
        : `${20 + (index * 660) / Math.max(trend.value.length - 1, 1)},${120 - point.score}`
    )
    .filter(Boolean)
    .join(' ')
);
const date = value => formatDate(value, props.metadata.formatting);
</script>

<template>
  <section
    class="space-y-4"
    data-testid="health-score-view"
  >
    <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
      <button
        :class="buttonClass"
        class="flex-col p-4"
        :disabled="metrics.health_average == null"
        @click="emit('inspect', 'health_average')"
      >
        <span>{{ t('RELATIONSHIP.METRICS.health_average') }}</span
        ><strong class="text-xl">{{
          metrics.health_average?.toFixed(1) ?? t('RELATIONSHIP.UNAVAILABLE')
        }}</strong>
      </button>
      <button
        v-for="band in bands"
        :key="band"
        :class="buttonClass"
        class="flex-col p-4"
        @click="emit('filter', { band })"
      >
        <span>{{ t(`RELATIONSHIP.BANDS.${band}`) }}</span
        ><strong class="text-xl">{{ metrics.bands?.[band] ?? 0 }}</strong>
      </button>
    </div>
    <p
      v-if="metrics.health_coverage"
      class="text-xs text-n-slate-11"
    >
      {{ t('RELATIONSHIP.HEALTH_COVERAGE', metrics.health_coverage) }}
    </p>
    <section class="rounded-xl border border-n-weak p-4">
      <h3 class="font-semibold">{{ t('RELATIONSHIP.HEALTH_TREND') }}</h3>
      <p
        v-if="metrics.health_comparison_period"
        class="text-xs text-n-slate-11"
      >
        {{ date(metrics.health_comparison_period.from) }}
        {{ t('RELATIONSHIP.ARROW') }}
        {{ date(metrics.health_comparison_period.to) }}
      </p>
      <template v-if="trend.length">
        <svg
          viewBox="0 0 700 150"
          role="img"
          :aria-label="t('RELATIONSHIP.HEALTH_TREND')"
          class="h-40 w-full text-n-brand"
        >
          <line
            x1="20"
            y1="120"
            x2="680"
            y2="120"
            stroke="currentColor"
          />
          <polyline
            :points="points"
            fill="none"
            stroke="currentColor"
            stroke-width="3"
          />
          <template
            v-for="(point, index) in trend"
            :key="point.day"
          >
            <circle
              v-if="point.score != null"
              :cx="20 + (index * 660) / Math.max(trend.length - 1, 1)"
              :cy="120 - point.score"
              r="4"
              fill="currentColor"
            />
          </template>
        </svg>
        <details>
          <summary>{{ t('RELATIONSHIP.HISTORY') }}</summary>
          <button
            v-for="point in trend"
            :key="point.day"
            :class="buttonClass"
            :disabled="point.score == null"
            @click="
              emit('inspect', { metric: 'health_average', day: point.day })
            "
          >
            {{ date(point.day) }} · {{ point.score?.toFixed(1) ?? '—' }}
          </button>
        </details>
      </template>
      <p
        v-else
        class="mt-2 text-sm text-n-slate-11"
      >
        {{ t('RELATIONSHIP.NO_HEALTH_HISTORY') }}
      </p>
    </section>
    <div class="grid gap-4 md:grid-cols-2">
      <section
        v-for="key in ['most_declined', 'most_improved']"
        :key="key"
        class="rounded-xl border border-n-weak p-4"
      >
        <h3 class="mb-2 font-semibold">
          {{ t(`RELATIONSHIP.HEALTH.${key}`) }}
        </h3>
        <p
          v-if="!metrics[key]?.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.NO_HEALTH_CHANGE') }}
        </p>
        <button
          v-for="row in metrics[key] || []"
          :key="row.assignment_id"
          :class="buttonClass"
          class="mb-2 w-full justify-between"
          @click="emit('open', row.assignment_id)"
        >
          <span>{{ row.customer }}</span
          ><span
            >{{ row.previous }} {{ t('RELATIONSHIP.ARROW') }}
            {{ row.current }} ({{ row.delta > 0 ? '+' : ''
            }}{{ row.delta }})</span
          >
        </button>
      </section>
      <section
        v-for="direction in ['negative', 'positive']"
        :key="direction"
        class="rounded-xl border border-n-weak p-4"
      >
        <h3 class="mb-2 font-semibold">
          {{ t(`RELATIONSHIP.HEALTH.${direction}_factors`) }}
        </h3>
        <p
          v-if="!metrics[`${direction}_factors`]?.length"
          class="text-sm text-n-slate-11"
        >
          {{ t('RELATIONSHIP.UNAVAILABLE') }}
        </p>
        <button
          v-for="row in metrics[`${direction}_factors`] || []"
          :key="row.factor"
          :class="buttonClass"
          class="mb-2 w-full justify-between"
          @click="emit('filter', { factor: row.factor, direction })"
        >
          <span>{{ t(`RELATIONSHIP.FACTORS.${row.factor}`) }}</span
          ><span
            >{{ row.average }} ·
            {{
              t('RELATIONSHIP.CUSTOMER_COUNT', { count: row.customers })
            }}</span
          >
        </button>
      </section>
    </div>
    <div
      v-if="rows.length"
      class="overflow-x-auto rounded-xl border border-n-weak"
    >
      <table class="w-full text-left text-sm">
        <thead class="bg-n-alpha-2">
          <tr>
            <th
              v-for="key in [
                'customer',
                'health',
                'last_calculation',
                'evidence',
              ]"
              :key="key"
              class="p-3"
            >
              {{ t(`RELATIONSHIP.FIELDS.${key}`) }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.id"
            class="border-t border-n-weak"
          >
            <td class="p-3">
              <button
                class="text-n-brand"
                @click="emit('open', row.id)"
              >
                {{ row.name }}
              </button>
            </td>
            <td class="p-3">
              {{ row.signals.health?.score ?? '—' }} ·
              {{
                t(
                  `RELATIONSHIP.BANDS.${row.signals.health?.band || 'unavailable'}`
                )
              }}
            </td>
            <td class="p-3">{{ date(row.calculated_at) }}</td>
            <td class="p-3">
              <button
                :class="buttonClass"
                @click="emit('open', row.id)"
              >
                {{ t('RELATIONSHIP.EXPLAIN') }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>
