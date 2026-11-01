<script setup>
import { computed, ref } from 'vue';
import { useBackofficeWorkspace } from './useBackofficeWorkspace';
import { stages, useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({ report: { type: Boolean, default: false } });
const { text, label, destination } = useBackofficePresentation();
const { result, loading, error, load } = useBackofficeWorkspace(
  props.report ? 'reports' : 'overview',
  {
    status: '',
    per_page: 5,
  }
);
const tab = ref('indicators');
const metrics = [
  'active',
  'overdue',
  'blocked',
  'waiting_customer',
  'critical',
  'completed',
];
const queueRows = computed(() =>
  Object.entries(result.value?.summary.queues || {}).map(([id, count]) => ({
    id,
    name:
      result.value.options.queues.find(queue => String(queue.id) === id)
        ?.name || (id ? `${text('QUEUE_REFERENCE')} #${id}` : text('NO_QUEUE')),
    count,
  }))
);
</script>

<template>
  <div
    class="space-y-5"
    :aria-busy="loading"
  >
    <div class="flex items-center justify-between gap-3">
      <h2 class="text-xl font-bold">
        {{ text(report ? 'NAV.reports' : 'NAV.overview') }}
      </h2>
      <button
        class="rounded-lg border border-emerald-300 bg-n-solid-2 px-4 py-2 text-sm font-semibold text-emerald-700 disabled:opacity-50"
        :disabled="loading"
        @click="load()"
      >
        {{ text('REFRESH') }}
      </button>
    </div>
    <p class="text-sm text-n-slate-11">{{ text('SCOPE_NOTE') }}</p>
    <p
      v-if="loading"
      role="status"
      class="rounded-xl border bg-n-solid-2 p-8"
    >
      {{ text('LOADING') }}
    </p>
    <p
      v-else-if="error"
      role="alert"
      class="rounded-xl border border-red-200 bg-red-50 p-5 text-red-700"
    >
      {{ text('LOAD_ERROR') }}
    </p>
    <template v-else-if="result">
      <nav
        class="flex flex-wrap gap-2"
        :aria-label="text('OVERVIEW_TABS_LABEL')"
      >
        <button
          v-for="item in [
            'indicators',
            'stages',
            'queues',
            'recent',
            ...(report ? ['types'] : []),
          ]"
          :key="item"
          class="rounded-lg border px-4 py-2 text-sm font-semibold"
          :class="
            tab === item
              ? 'border-emerald-600 bg-emerald-600 text-white'
              : 'border-n-weak bg-n-solid-2'
          "
          :aria-pressed="tab === item"
          @click="tab = item"
        >
          {{ text(`OVERVIEW_TABS.${item}`) }}
        </button>
      </nav>
      <section
        v-if="tab === 'indicators'"
        class="grid gap-3 sm:grid-cols-3"
      >
        <article
          v-for="metric in metrics"
          :key="metric"
          class="rounded-2xl border border-n-weak border-t-4 bg-n-solid-2 p-5 shadow-sm"
          :class="
            metric === 'overdue'
              ? 'border-t-red-500'
              : metric === 'blocked'
                ? 'border-t-amber-500'
                : 'border-t-emerald-500'
          "
        >
          <p class="text-sm text-n-slate-11">{{ text(`METRICS.${metric}`) }}</p>
          <strong class="mt-2 block text-3xl">
            {{ result.summary[metric] }}
          </strong>
        </article>
      </section>
      <section v-if="['stages', 'queues'].includes(tab)">
        <article
          v-if="tab === 'stages'"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <h3 class="font-bold">{{ text('STAGE_DISTRIBUTION') }}</h3>
          <p class="mt-1 text-xs text-n-slate-11">{{ text('ACTIVE_ONLY') }}</p>
          <div class="mt-4 grid gap-3 sm:grid-cols-2">
            <RouterLink
              v-for="stage in stages.filter(item => item !== 'completed')"
              :key="stage"
              :to="{
                name: 'crm_backoffice',
                params: { section: 'requests' },
                query: { stage },
              }"
              class="flex items-center justify-between gap-2 rounded-xl border border-n-weak bg-n-slate-2 p-3 hover:border-emerald-400"
            >
              <span class="text-sm">{{ label(stage) }}</span>
              <b class="text-lg text-emerald-700">
                {{ result.summary.stages[stage] || 0 }}
              </b>
            </RouterLink>
          </div>
        </article>
        <article
          v-if="tab === 'queues'"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <h3 class="font-bold">{{ text('QUEUE_DISTRIBUTION') }}</h3>
          <p class="mt-1 text-xs text-n-slate-11">{{ text('ACTIVE_ONLY') }}</p>
          <div class="mt-4 space-y-3">
            <div
              v-for="queue in queueRows"
              :key="queue.id"
              class="flex justify-between gap-3 rounded-xl border border-emerald-100 bg-emerald-50 p-4 text-emerald-900"
            >
              <span>{{ queue.name }}</span>
              <b>{{ queue.count }}</b>
            </div>
            <p
              v-if="!queueRows.length"
              class="py-8 text-center text-sm text-n-slate-11"
            >
              {{ text('EMPTY') }}
            </p>
          </div>
        </article>
      </section>
      <section
        v-if="tab === 'types'"
        class="space-y-4"
      >
        <div class="rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm">
          {{ text('AVERAGE_OPEN') }}
          <b>{{ result.summary.average_open_hours }} {{ text('HOURS') }}</b>
        </div>
        <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <article
            v-for="item in result.summary.kinds"
            :key="item.kind"
            class="rounded-xl border border-n-weak bg-n-solid-2 p-4"
          >
            <h3 class="font-semibold">{{ label(item.kind) }}</h3>
            <p class="mt-3 text-2xl font-bold">
              {{ Math.round(((item.total - item.overdue) / item.total) * 100)
              }}{{ text('PERCENT') }}
            </p>
            <p class="mt-2 text-xs text-n-slate-11">
              {{ item.overdue }} {{ text('METRICS.overdue') }}
              {{ text('SEPARATOR') }} {{ item.total }} {{ text('RESULTS') }}
            </p>
          </article>
        </div>
      </section>
      <section
        v-if="tab === 'recent'"
        class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
      >
        <h3 class="font-bold">{{ text('RECENT') }}</h3>
        <RouterLink
          v-for="item in result.data"
          :key="item.id"
          :to="destination(item.id)"
          class="mt-3 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak p-4 hover:border-emerald-400"
        >
          <div>
            <b class="text-sm text-emerald-700">{{ item.request_number }}</b>
            <p class="text-sm">{{ item.title }}</p>
          </div>
          <span class="rounded-lg bg-n-slate-3 px-3 py-1 text-xs">
            {{ label(item.status) }}
          </span>
        </RouterLink>
        <p
          v-if="!result.data.length"
          class="py-8 text-center text-sm text-n-slate-11"
        >
          {{ text('EMPTY') }}
        </p>
      </section>
    </template>
  </div>
</template>
