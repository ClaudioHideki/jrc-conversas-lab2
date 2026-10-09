<script setup>
import { computed } from 'vue';
import { v2Labels } from '../helpers/v2Labels';
import { useI18n } from 'vue-i18n';
import Panel from './ServiceDeskPanel.vue';
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
                <dd class="text-xl tabular-nums">
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
        <dl class="grid grid-cols-2 gap-3">
          <template v-for="(value, key) in data.sla" :key="key">
            <dt>{{ labels.supervisor[key] }}</dt>
            <dd class="tabular-nums">
              {{
                value === null
                  ? t('JRC_SERVICE_DESK.COMMON.no_value')
                  : Number(value.toFixed(2))
              }}
            </dd>
          </template>
        </dl>
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
            class="flex items-center gap-3 mb-2"
          >
            <p class="text-sm w-28 shrink-0 break-words sm:w-36">
              {{
                row.date || row.name || t('JRC_SERVICE_DESK.COMMON.no_value')
              }}
            </p>
            <progress
              class="min-w-0 flex-1"
              :value="row.count"
              :max="maximum(data[kind])"
              :aria-label="
                row.date || row.name || t('JRC_SERVICE_DESK.COMMON.no_value')
              "
            />
            <span class="tabular-nums">{{ row.count }} </span>
          </div>
        </Panel>
        <Panel :title="t('JRC_SERVICE_DESK.V2.capacity')">
          <p v-if="!data.capacity.length">
            {{ t('JRC_SERVICE_DESK.COMMON.no_records') }}
          </p>
          <div
            v-for="row in data.capacity"
            :key="row.id"
            class="flex flex-wrap items-center gap-3 mb-2 text-sm"
          >
            <span class="flex-1">{{ row.name }} </span>
            <span>{{ labels.availability[row.availability] }} </span>
            <span class="tabular-nums">
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
