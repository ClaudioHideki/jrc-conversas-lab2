<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import HelpdeskKpis from './HelpdeskKpis.vue';
import {
  helpdeskDate,
  helpdeskRows,
  helpdeskValue,
} from './helpdeskPresentation';
const props = defineProps({
  report: { type: Object, required: true },
  options: { type: Object, default: () => ({}) },
});
const { t } = useI18n();
const value = item => helpdeskValue(item, t('JRC_NICO_HELPDESK.NO_DATA'));
const date = item =>
  helpdeskDate(item, t('JRC_NICO_HELPDESK.NO_DATA'), props.report.timezone);
const name = (kind, id) =>
  props.options[kind]?.find(item => String(item.id) === String(id))?.name ||
  value(id);
const rows = computed(() =>
  helpdeskRows(
    props.report.evidence_resources || {},
    t('JRC_NICO_HELPDESK.NO_DATA')
  )
);
const hours = seconds =>
  Number.isFinite(seconds)
    ? (seconds / 3600).toFixed(1)
    : t('JRC_NICO_HELPDESK.NO_DATA');
</script>

<template>
  <section
    class="space-y-4 overflow-auto rounded-xl border border-n-weak p-4"
    data-testid="helpdesk-daily-report"
  >
    <h2 class="text-lg font-semibold">{{ t('JRC_NICO_HELPDESK.REPORT') }}</h2>
    <p v-if="report.preview" class="text-xs text-n-slate-11">
      {{ t('JRC_NICO_HELPDESK.PREVIEW_ONLY') }}
    </p>
    <p class="text-sm">
      {{
        t('JRC_NICO_HELPDESK.REPORT_CUTOFF', {
          cutoff: date(report.cutoff_at),
          zone: report.timezone,
        })
      }}
    </p>
    <p v-if="report.window" class="break-all text-sm">
      {{ t('JRC_NICO_HELPDESK.REPORT_INTERVAL', report.window) }} ·
      {{ report.window.basis }}
    </p>
    <div class="grid gap-3 text-sm md:grid-cols-2">
      <div>
        <h3 class="font-medium">
          {{ t('JRC_NICO_HELPDESK.NEW_OVERDUE') }}
          {{ (report.new_overdue_today || []).length }}
        </h3>
        <p>
          {{ t('JRC_NICO_HELPDESK.NEW_EVENTS') }}
          {{
            (report.new_event_ids || []).join(', ') ||
            t('JRC_NICO_HELPDESK.EMPTY')
          }}
        </p>
      </div>
      <div>
        <h3 class="font-medium">
          {{ t('JRC_NICO_HELPDESK.BACKLOG') }}
          {{ (report.previous_backlog || []).length }}
        </h3>
        <p>
          {{ t('JRC_NICO_HELPDESK.PREVIOUS_EVENTS') }}
          {{
            (report.previous_event_ids || []).join(', ') ||
            t('JRC_NICO_HELPDESK.EMPTY')
          }}
        </p>
      </div>
    </div>
    <table class="w-full text-left text-sm">
      <thead>
        <tr>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.TICKET') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.COMPANIES') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.UNITS') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.DUE') }}</th>
          <th class="p-2">{{ t('JRC_NICO_HELPDESK.OVERDUE') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="ticket in report.overdue || []"
          :key="ticket.ticket_id"
          class="border-t border-n-weak"
        >
          <td class="p-2">{{ ticket.ticket_id }}</td>
          <td class="p-2">{{ name('companies', ticket.company_id) }}</td>
          <td class="p-2">{{ name('units', ticket.unit_id) }}</td>
          <td class="p-2">{{ date(ticket.due_at) }}</td>
          <td class="p-2">
            {{
              t('JRC_NICO_HELPDESK.OVERDUE_HOURS', {
                calendar: hours(ticket.overdue_calendar_seconds),
                business: hours(ticket.overdue_business_seconds),
              })
            }}
          </td>
        </tr>
      </tbody>
    </table>
    <dl class="grid gap-3 text-sm md:grid-cols-3">
      <div>
        <dt>{{ t('JRC_NICO_HELPDESK.COMPLAINTS') }}</dt>
        <dd>
          {{
            (report.complaints || []).join(', ') || t('JRC_NICO_HELPDESK.EMPTY')
          }}
        </dd>
      </div>
      <div>
        <dt>{{ t('JRC_NICO_HELPDESK.LEGAL_INTERNAL') }}</dt>
        <dd>
          {{
            (report.legal_risk_internal_only || []).join(', ') ||
            t('JRC_NICO_HELPDESK.EMPTY')
          }}
        </dd>
      </div>
      <div>
        <dt>{{ t('JRC_NICO_HELPDESK.RECURRENT') }}</dt>
        <dd>
          {{
            (report.recurrent || []).join(', ') || t('JRC_NICO_HELPDESK.EMPTY')
          }}
        </dd>
      </div>
    </dl>
    <HelpdeskKpis v-if="report.kpis" :report="report.kpis" />
    <details v-if="rows.length" class="text-xs">
      <summary>{{ t('JRC_NICO_HELPDESK.EVIDENCE') }}</summary>
      <dl>
        <div v-for="row in rows" :key="row.field" class="mt-2">
          <dt>{{ row.field }}</dt>
          <dd>{{ row.value }}</dd>
        </div>
      </dl>
    </details>
  </section>
</template>
