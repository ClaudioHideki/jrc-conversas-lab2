<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import HelpdeskDailyReport from './HelpdeskDailyReport.vue';
import { helpdeskDate, helpdeskValue } from './helpdeskPresentation';
defineProps({
  history: { type: Object, required: true },
  detail: { type: Object, default: null },
  options: { type: Object, default: () => ({}) },
  busy: Boolean,
});
defineEmits(['select', 'next']);
const { t } = useI18n();
const value = item => helpdeskValue(item, t('JRC_NICO_HELPDESK.NO_DATA'));
const date = (item, zone) =>
  helpdeskDate(item, t('JRC_NICO_HELPDESK.NO_DATA'), zone);
const receiptStates = computed(() => ({
  pending: t('JRC_NICO_HELPDESK.STATES.pending'),
  dispatching: t('JRC_NICO_HELPDESK.RECEIPT_STATES.dispatching'),
  sent: t('JRC_NICO_HELPDESK.RECEIPT_STATES.sent'),
  delivered: t('JRC_NICO_HELPDESK.RECEIPT_STATES.delivered'),
  failed: t('JRC_NICO_HELPDESK.STATES.failed'),
  blocked: t('JRC_NICO_HELPDESK.STATES.blocked'),
  unknown: t('JRC_NICO_HELPDESK.STATES.unknown'),
}));
</script>

<template>
  <section
    class="space-y-4 rounded-xl border border-n-weak p-4"
    data-testid="helpdesk-report-history"
  >
    <h2 class="text-lg font-semibold">
      {{ t('JRC_NICO_HELPDESK.REPORT_HISTORY') }}
    </h2>
    <p class="text-sm text-n-slate-11">
      {{ t('JRC_NICO_HELPDESK.DAILY_NATIVE_GENERATION') }}
    </p>
    <p v-if="!history.reports.length">{{ t('JRC_NICO_HELPDESK.EMPTY') }}</p>
    <article
      v-for="report in history.reports"
      :key="report.id"
      class="rounded border border-n-weak p-3"
    >
      <button
        :disabled="busy"
        class="rounded border border-n-weak px-3 py-1"
        :data-report-id="report.id"
        @click="$emit('select', report.id)"
      >
        {{ report.report_date }} ·
        {{
          t('JRC_NICO_HELPDESK.REPORT_CUTOFF', {
            cutoff: date(report.cutoff_at, report.timezone),
            zone: report.timezone,
          })
        }}
      </button>
      <table class="mt-3 w-full text-left text-xs">
        <thead>
          <tr>
            <th class="p-2">{{ t('JRC_NICO_HELPDESK.RECEIPT_CHANNEL') }}</th>
            <th class="p-2">{{ t('JRC_NICO_HELPDESK.STATE') }}</th>
            <th class="p-2">{{ t('JRC_NICO_HELPDESK.RECEIPT_TIMES') }}</th>
            <th class="p-2">{{ t('JRC_NICO_HELPDESK.RECEIPT_ATTEMPT') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="receipt in report.receipts || []"
            :key="receipt.id"
            class="border-t border-n-weak"
          >
            <td class="p-2">{{ receipt.channel }}</td>
            <td class="p-2">
              {{ receiptStates[receipt.state] || value(receipt.state) }}
              <p>{{ value(receipt.reason) }}</p>
            </td>
            <td class="p-2">
              {{
                t('JRC_NICO_HELPDESK.RECEIPT_SENT', {
                  at: date(receipt.sent_at, report.timezone),
                })
              }}
              <p>
                {{
                  t('JRC_NICO_HELPDESK.RECEIPT_DELIVERED', {
                    at: date(receipt.delivered_at, report.timezone),
                  })
                }}
              </p>
            </td>
            <td class="p-2">{{ value(receipt.attempt_number) }}</td>
          </tr>
        </tbody>
      </table>
    </article>
    <button
      v-if="history.next_page"
      :disabled="busy"
      class="rounded border border-n-weak px-3 py-1"
      @click="$emit('next', history.next_page)"
    >
      {{ t('JRC_NICO_HELPDESK.NEXT_PAGE') }}
    </button>
    <HelpdeskDailyReport
      v-if="detail"
      :report="detail.payload"
      :options="options"
    />
  </section>
</template>
