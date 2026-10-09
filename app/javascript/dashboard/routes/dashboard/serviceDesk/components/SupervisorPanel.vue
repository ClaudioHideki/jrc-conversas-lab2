<script setup>
import { computed } from 'vue';
import { v2Labels } from '../helpers/v2Labels';
import { useI18n } from 'vue-i18n';
import Panel from './ServiceDeskPanel.vue';
const props = defineProps({ data: { type: Object, default: null } });
const { t } = useI18n();
const labels = computed(() => v2Labels(t));
const capacitySeparator = '/';
const maximum = rows => Math.max(1, ...rows.map(row => row.count));
</script>

<template>
  <div class="grid gap-4">
    <template v-if="props.data">
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
      <div class="grid gap-4 lg:grid-cols-2">
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
            <p class="text-sm w-36 break-words">
              {{
                row.date || row.name || t('JRC_SERVICE_DESK.COMMON.no_value')
              }}
            </p>
            <progress
              class="flex-1"
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
  </div>
</template>
