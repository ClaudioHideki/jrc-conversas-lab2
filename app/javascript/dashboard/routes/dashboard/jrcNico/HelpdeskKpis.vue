<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { buildHelpdeskLabels } from './helpdeskLabels';
import HelpdeskMetricEvidence from './HelpdeskMetricEvidence.vue';
import {
  helpdeskRows,
  helpdeskValue,
  helpdeskMetricValue,
} from './helpdeskPresentation';

defineProps({ report: { type: Object, required: true } });
const { t } = useI18n();
const label = computed(() => buildHelpdeskLabels(t));
const value = item => helpdeskValue(item, t('JRC_NICO_HELPDESK.NO_DATA'));
const rows = item => helpdeskRows(item, t('JRC_NICO_HELPDESK.NO_DATA'));
</script>

<template>
  <section
    class="overflow-auto rounded-xl border border-n-weak p-4"
    data-testid="helpdesk-kpis"
  >
    <h2 class="mb-3 text-lg font-semibold">
      {{ t('JRC_NICO_HELPDESK.KPIS') }}
    </h2>
    <p class="mb-3 break-all text-sm">
      {{
        t('JRC_NICO_HELPDESK.REPORT_INTERVAL', {
          from: report.interval.from,
          until: report.interval.until,
        })
      }}
    </p>
    <table class="w-full text-left text-sm">
      <thead>
        <tr>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.KPIS') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.FORMULA') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.NUMERATOR') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.DENOMINATOR') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.RESULT') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="metric in report.metrics"
          :key="metric.key"
          class="border-t border-n-weak"
          :data-testid="`helpdesk-kpi-${metric.key}`"
        >
          <th class="p-2">
            {{ metric.key }} {{ label('kpiNames', metric.key) }}
          </th>
          <td class="p-2">
            {{ label('kpiFormulas', metric.key) }}
            <p class="mt-1 text-xs text-n-slate-11">{{ metric.formula }}</p>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ t('JRC_NICO_HELPDESK.REPORT_INTERVAL', metric.window) }}
            </p>
            <p v-if="metric.target" class="mt-1 text-xs">
              {{ t('JRC_NICO_HELPDESK.TARGET', { target: metric.target }) }}
            </p>
            <HelpdeskMetricEvidence :metric="metric" />
            <details class="mt-2 text-xs">
              <summary>{{ t('JRC_NICO_HELPDESK.EVIDENCE') }}</summary>
              <dl>
                <div
                  v-for="row in rows(metric.evidence)"
                  :key="row.field"
                  class="mt-1"
                >
                  <dt>{{ row.field }}</dt>
                  <dd>{{ row.value }}</dd>
                </div>
              </dl>
            </details>
          </td>
          <td class="p-2">{{ value(metric.numerator) }}</td>
          <td class="p-2">{{ value(metric.denominator) }}</td>
          <td class="p-2">
            {{ helpdeskMetricValue(metric, t('JRC_NICO_HELPDESK.NO_DATA')) }}
            <p v-if="metric.reason" class="mt-1 text-xs text-n-slate-11">
              {{ metric.reason }}
            </p>
          </td>
        </tr>
      </tbody>
    </table>
  </section>
</template>
