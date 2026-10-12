<script setup>
import { computed } from 'vue';
import { v2Labels } from '../helpers/v2Labels';
import { useI18n } from 'vue-i18n';
import Panel from './ServiceDeskPanel.vue';
import MetricRing from './MetricRing.vue';
import { tones, metricTones } from '../helpers/visualTheme';
const props = defineProps({
  data: { type: Object, default: null },
  compact: { type: Boolean, default: false },
});
const { t } = useI18n();
const labels = computed(() => v2Labels(t));
const capacitySeparator = '/';
const maximum = rows => Math.max(1, ...rows.map(row => row.count));
</script>

<template>
  <div class="grid gap-4">
    <template v-if="props.data">
      <div class="grid gap-3 sm:grid-cols-2">
        <section
          v-for="kind in ['tasks', 'approvals']"
          v-show="data[kind]"
          :key="kind"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <h3 class="font-semibold text-sm">
            {{ t(`JRC_SERVICE_DESK.SCREENS.${kind}`) }}
          </h3>
          <template v-if="data[kind]">
            <dl class="mt-3 grid grid-cols-2 gap-3">
              <div>
                <dt class="text-xs text-n-slate-11">
                  {{ t('JRC_SERVICE_DESK.EXPERIENCE.pending') }}
                </dt>
                <dd class="text-xl font-bold tabular-nums text-n-amber-11">
                  {{
                    kind === 'tasks' ? data.tasks.open : data.approvals.pending
                  }}
                </dd>
              </div>
              <div>
                <dt class="text-xs text-n-slate-11">
                  {{ t('JRC_SERVICE_DESK.EXPERIENCE.overdue') }}
                </dt>
                <dd class="text-xl tabular-nums text-n-ruby-11">
                  {{ data[kind].overdue }}
                </dd>
              </div>
            </dl>
          </template>
        </section>
      </div>
      <p
        v-if="compact && !data.sla"
        role="status"
        class="text-sm text-n-slate-11"
      >
        {{ t('JRC_SERVICE_DESK.EXPERIENCE.sla_unavailable') }}
      </p>
      <Panel v-if="data.sla" :title="t('JRC_SERVICE_DESK.V2.sla')">
        <dl class="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <div
            v-for="(value, key) in data.sla"
            :key="key"
            class="rounded-xl p-3"
            :class="tones[metricTones[key] || 'iris'].soft"
          >
            <dt class="text-xs font-medium">{{ labels.supervisor[key] }}</dt>
            <dd class="mt-2 text-xl font-bold tabular-nums">
              {{
                value === null
                  ? t('JRC_SERVICE_DESK.COMMON.no_value')
                  : Number(value.toFixed(2))
              }}
            </dd>
          </div>
        </dl>
        <div
          class="mt-4 grid gap-3 md:grid-cols-3"
          data-testid="sla-measured-bars"
        >
          <div
            v-for="key in [
              'running_breached',
              'completed_met',
              'completed_breached',
            ]"
            :key="key"
            class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-2 p-3 text-sm"
          >
            <span
              class="min-w-0 flex-1 font-medium"
              :class="tones[metricTones[key]].text"
              >{{ labels.supervisor[key] }}</span
            >
            <MetricRing
              :class="tones[metricTones[key]].text"
              :value="data.sla[key]"
              :maximum="Math.max(data.sla.observed_cycles, data.sla[key], 1)"
              :label="labels.supervisor[key]"
            />
          </div>
        </div>
      </Panel>
      <div v-if="!compact" class="grid gap-4 lg:grid-cols-2">
        <Panel
          v-for="kind in ['evolution', 'top_categories', 'by_agent']"
          :key="kind"
          :title="labels.supervisor[kind]"
        >
          <p v-if="!data[kind].length">
            {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
          </p>
          <div
            v-for="row in data[kind]"
            :key="row.date || row.id || 'unassigned'"
            class="mb-3 flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-3"
          >
            <p class="text-sm w-28 shrink-0 break-words sm:w-36">
              {{
                row.date || row.name || t('JRC_SERVICE_DESK.COMMON.no_value')
              }}
            </p>
            <MetricRing
              :class="
                kind === 'top_categories'
                  ? 'text-n-iris-11'
                  : kind === 'by_agent'
                    ? 'text-n-teal-11'
                    : 'text-n-blue-11'
              "
              :value="row.count"
              :maximum="maximum(data[kind])"
              :label="
                row.date || row.name || t('JRC_SERVICE_DESK.COMMON.no_value')
              "
            />
          </div>
        </Panel>
        <Panel :title="t('JRC_SERVICE_DESK.V2.capacity')">
          <p v-if="!data.capacity.length">
            {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
          </p>
          <div
            v-for="row in data.capacity"
            :key="row.id"
            class="mb-3 flex flex-wrap items-center gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-3 text-sm"
          >
            <span class="flex-1">{{ row.name }} </span>
            <span>{{ labels.availability[row.availability] }} </span>
            <span class="tabular-nums font-bold text-n-blue-11">
              {{ row.active_tickets }} {{ capacitySeparator }}
              {{
                row.capacity === null
                  ? t('JRC_SERVICE_DESK.COMMON.no_value')
                  : row.capacity
              }}
            </span>
          </div>
        </Panel>
      </div>
      <p class="text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.V2.observed_help') }}
      </p>
    </template>
    <p v-else class="text-sm text-n-slate-11" role="status">
      {{ t('JRC_SERVICE_DESK.COMMON.not_available') }}
    </p>
  </div>
</template>
