<script setup>
import { computed } from 'vue';
import { statusStrokes, statusDots } from './backofficeVisuals';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({ summary: { type: Object, required: true } });
const { text, label } = useBackofficePresentation();
const circumference = Math.PI * 92;
const segments = computed(() => {
  let offset = 0;
  return Object.entries(props.summary.statuses)
    .filter(([, count]) => count > 0)
    .map(([status, count]) => {
      const length = props.summary.total
        ? (circumference * count) / props.summary.total
        : 0;
      const row = {
        status,
        count,
        offset: -offset,
        dash: `${length} ${circumference}`,
      };
      offset += length;
      return row;
    });
});
const duration = seconds => {
  if (seconds === null) return text('DASHBOARD.NO_MEASUREMENTS');
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);
  return days
    ? `${days}${text('DASHBOARD.DAYS_SHORT')} ${hours % 24}${text('DASHBOARD.HOURS_SHORT')}`
    : `${hours}${text('DASHBOARD.HOURS_SHORT')} ${minutes % 60}${text('DASHBOARD.MINUTES_SHORT')}`;
};
</script>

<template>
  <div class="grid items-start gap-4 xl:grid-cols-3">
    <section
      class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
    >
      <h3 class="mb-4 flex items-center gap-2 font-semibold">
        <span
          class="i-lucide-chart-pie size-5 text-blue-600 dark:text-blue-300"
        />
        {{ text('DASHBOARD.STATUS_CHART') }}
      </h3>
      <div class="flex flex-wrap items-center justify-center gap-4">
        <div class="relative size-32 shrink-0">
          <svg
            viewBox="0 0 120 120"
            class="size-full"
            role="img"
            :aria-label="text('DASHBOARD.STATUS_CHART')"
          >
            <circle
              cx="60"
              cy="60"
              r="46"
              fill="none"
              stroke-width="13"
              class="stroke-n-slate-3"
            />
            <circle
              v-for="segment in segments"
              :key="segment.status"
              cx="60"
              cy="60"
              r="46"
              fill="none"
              stroke-width="13"
              transform="rotate(-90 60 60)"
              :stroke-dasharray="segment.dash"
              :stroke-dashoffset="segment.offset"
              :class="statusStrokes[segment.status]"
            />
          </svg>
          <div
            class="absolute inset-0 grid content-center justify-items-center"
          >
            <b class="text-3xl">{{ summary.total }}</b>
            <span class="text-xs text-n-slate-11">{{ text('RESULTS') }}</span>
          </div>
        </div>
        <ul class="min-w-0 flex-1 space-y-2 text-xs">
          <li
            v-for="segment in segments"
            :key="segment.status"
            class="flex items-center justify-between gap-2"
          >
            <span class="flex min-w-0 items-center gap-2">
              <span
                class="size-2 shrink-0 rounded-full"
                :class="statusDots[segment.status]"
              />
              <span
                class="truncate"
                :title="label(segment.status)"
              >
                {{ label(segment.status) }}
              </span>
            </span>
            <b>{{ segment.count }}</b>
          </li>
          <li
            v-if="!segments.length"
            class="text-n-slate-11"
          >
            {{ text('EMPTY') }}
          </li>
        </ul>
      </div>
    </section>
    <section
      class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
    >
      <h3 class="mb-4 flex items-center gap-2 font-semibold">
        <span
          class="i-lucide-chart-bar size-5 text-violet-600 dark:text-violet-300"
        />
        {{ text('DASHBOARD.KIND_CHART') }}
      </h3>
      <div class="space-y-4">
        <div
          v-for="item in summary.kinds"
          :key="item.kind"
          class="text-xs"
        >
          <div class="mb-1 flex items-center justify-between gap-3">
            <span>{{ label(item.kind) }}</span>
            <b>{{ item.total }}</b>
          </div>
          <progress
            :max="summary.total"
            :value="item.total"
            :aria-label="label(item.kind)"
            class="block h-2 w-full overflow-hidden rounded-full bg-n-slate-3 [&::-webkit-progress-bar]:bg-n-slate-3 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-violet-500 [&::-moz-progress-bar]:bg-violet-500"
          />
          <p
            v-if="item.overdue"
            class="mt-1 text-rose-700 dark:text-rose-300"
          >
            {{ item.overdue }} {{ text('METRICS.overdue') }}
          </p>
        </div>
        <p
          v-if="!summary.kinds.length"
          class="text-sm text-n-slate-11"
        >
          {{ text('EMPTY') }}
        </p>
      </div>
    </section>
    <section
      class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
    >
      <h3 class="mb-4 flex items-center gap-2 font-semibold">
        <span class="i-lucide-timer size-5 text-teal-700 dark:text-teal-300" />
        {{ text('DASHBOARD.OBSERVED') }}
      </h3>
      <dl class="space-y-3">
        <div
          v-for="item in [
            {
              key: 'FIRST_RESPONSE',
              value: summary.observed.first_action_seconds,
            },
            {
              key: 'COMPLETION_TIME',
              value: summary.observed.completion_seconds,
            },
          ]"
          :key="item.key"
          class="rounded-xl border border-n-weak bg-n-slate-2 p-3"
        >
          <dt class="text-xs text-n-slate-11">
            {{ text(`DASHBOARD.${item.key}`) }}
          </dt>
          <dd class="mt-1 text-xl font-bold">{{ duration(item.value) }}</dd>
        </div>
      </dl>
      <p class="mt-3 text-xs text-n-slate-11">
        {{ summary.observed.configured_sla }}
        {{ text('DASHBOARD.CONFIGURED_SLA') }}
      </p>
      <p class="mt-2 text-xs text-n-slate-11">
        {{ text('DASHBOARD.MEASUREMENT_NOTE') }}
      </p>
    </section>
  </div>
</template>
