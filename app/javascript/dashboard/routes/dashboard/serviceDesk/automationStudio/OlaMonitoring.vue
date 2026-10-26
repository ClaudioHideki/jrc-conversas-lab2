<script setup>
import { onBeforeUnmount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Insights from 'dashboard/api/serviceDeskAutomationInsights';
import LookupSelect from '../components/LookupSelect.vue';
import MetricCards from './MetricCards.vue';
const props = defineProps({
  accountId: { type: String, required: true },
  unitId: { type: String, required: true },
  queueId: { type: String, required: true },
});
const { t } = useI18n();
const tr = (key, values) =>
  t(`JRC_SERVICE_DESK.AUTOMATION_STUDIO.monitoring.${key}`, values || {});
const days = ref(30);
const assignee = ref('');
const team = ref('');
const page = ref(1);
const metrics = ref(null);
const alerts = ref(null);
const alertPage = ref(1);
const busy = ref(false);
const error = ref('');
const retrying = ref(null);
const reason = ref('');
let generation = 0;
let controller;
const parameters = (exporting = false) => ({
  queue_id: props.queueId,
  days: days.value,
  page: page.value,
  ...(assignee.value ? { assignee_account_user_id: assignee.value } : {}),
  ...(team.value ? { team_id: team.value } : {}),
  ...(exporting ? { export: 'true' } : {}),
});
async function load() {
  generation += 1;
  const turn = generation;
  controller?.abort();
  controller = new AbortController();
  busy.value = true;
  error.value = '';
  try {
    const value = await Insights.read(
      props.accountId,
      props.unitId,
      'ola',
      parameters(),
      controller.signal
    );
    const log = await Insights.read(
      props.accountId,
      props.unitId,
      'clock_alerts',
      { ...parameters(), page: alertPage.value },
      controller.signal
    );
    if (turn !== generation) return;
    metrics.value = value;
    alerts.value = log;
  } catch {
    if (turn === generation) error.value = tr('unavailable');
  } finally {
    if (turn === generation) busy.value = false;
  }
}
async function exportRows() {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    const value = await Insights.read(
      props.accountId,
      props.unitId,
      'ola',
      parameters(true),
      controller?.signal
    );
    const cell = input => {
      const text = String(input ?? '');
      return `"${(/^[=+@-]/.test(text) ? "'" : '') + text.replaceAll('"', '""')}"`;
    };
    const columns = [
      'ticket_id',
      'metric_kind',
      'state',
      'deadline_state',
      'elapsed_seconds',
      'budget_seconds',
      'due_at',
      'policy_revision',
    ];
    const csv = [
      columns,
      ...value.items.map(row => columns.map(key => row[key])),
    ]
      .map(row => row.map(cell).join(','))
      .join('\r\n');
    const url = URL.createObjectURL(
      new Blob(['\uFEFF', csv], { type: 'text/csv;charset=utf-8' })
    );
    const link = document.createElement('a');
    link.href = url;
    link.download = 'ola.csv';
    link.click();
    URL.revokeObjectURL(url);
  } catch {
    error.value = tr('export_error');
  } finally {
    busy.value = false;
  }
}
async function retry() {
  if (busy.value || !reason.value.trim()) return;
  busy.value = true;
  try {
    await Insights.retryAlert(
      props.accountId,
      props.unitId,
      retrying.value,
      reason.value
    );
    retrying.value = null;
    await load();
  } catch {
    error.value = tr('retry_error');
  } finally {
    busy.value = false;
  }
}
load();
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="min-w-0 space-y-4">
    <form
      class="grid gap-3 rounded-xl border border-n-blue-5 bg-n-blue-2 p-4 sm:grid-cols-2"
      @submit.prevent="
        page = 1;
        load();
      "
    >
      <label class="grid gap-1 text-sm">
        {{ tr('period') }}
        <select
          v-model.number="days"
          class="rounded-lg border bg-n-solid-1 p-2"
          :disabled="busy"
        >
          <option
            v-for="value in [7, 30, 60, 90]"
            :key="value"
            :value="value"
          >
            {{ tr('days', { count: value }) }}
          </option>
        </select>
      </label>
      <LookupSelect
        v-model="assignee"
        resource="assignees"
        :unit-id="unitId"
        :label="tr('assignee')"
        :disabled="busy"
      />
      <LookupSelect
        v-model="team"
        resource="teams"
        :unit-id="unitId"
        :label="tr('team')"
        :disabled="busy"
      />
      <div class="flex flex-wrap items-end gap-2">
        <button
          class="rounded-lg border bg-n-solid-1 px-3 py-2 text-sm"
          :disabled="busy"
        >
          {{ tr('refresh') }}
        </button>
        <button
          type="button"
          class="rounded-lg border bg-n-solid-1 px-3 py-2 text-sm"
          :disabled="busy"
          @click="exportRows"
        >
          {{ tr('export') }}
        </button>
      </div>
    </form>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-amber-2 p-3 text-sm"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ tr('loading') }}
    </p>
    <template v-if="metrics">
      <MetricCards
        :items="
          ['total', 'running', 'completed', 'overdue'].map(key => ({
            label: tr(key),
            value: key === 'total' ? metrics.total : metrics.counts[key] || 0,
          }))
        "
      />
      <p class="text-xs text-n-slate-11">{{ tr('historical') }}</p>
      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs">
          <thead>
            <tr>
              <th class="p-2">{{ tr('date') }}</th>
              <th class="p-2">{{ tr('measurements') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(value, date) in metrics.daily"
              :key="date"
              class="border-t"
            >
              <td class="p-2">{{ tr('date_utc', { date }) }}</td>
              <td class="p-2">
                <span
                  v-for="(count, state) in value"
                  :key="state"
                  class="mr-3"
                >
                  {{
                    t(
                      `JRC_SERVICE_DESK.AUTOMATION_STUDIO.clock_states.${state}`
                    )
                  }}: {{ count }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs">
          <thead>
            <tr>
              <th class="p-2">{{ tr('ticket') }}</th>
              <th class="p-2">{{ tr('metric') }}</th>
              <th class="p-2">{{ tr('state') }}</th>
              <th class="p-2">{{ tr('time') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in metrics.items"
              :key="row.id"
              class="border-t"
            >
              <td class="p-2">
                <a
                  :href="`/app/accounts/${accountId}/service-desk/tickets/${row.ticket_id}`"
                  class="text-n-blue-11 underline"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  #{{ row.ticket_id }} {{ row.title }}
                </a>
              </td>
              <td class="p-2">
                {{
                  t(
                    `JRC_SERVICE_DESK.AUTOMATION_STUDIO.ola.metric_${row.metric_kind}`
                  )
                }}
              </td>
              <td class="p-2">
                {{
                  t(
                    `JRC_SERVICE_DESK.AUTOMATION_STUDIO.clock_states.${row.deadline_state}`
                  )
                }}
              </td>
              <td class="p-2">
                {{ Math.round(row.elapsed_seconds / 60) }} /
                {{
                  tr('minutes', { count: Math.round(row.budget_seconds / 60) })
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="flex justify-between">
        <button
          :disabled="busy || page <= 1"
          @click="
            page -= 1;
            load();
          "
        >
          {{ tr('previous') }}
        </button>
        <span>{{ page }}</span>
        <button
          :disabled="busy || page * 25 >= metrics.total"
          @click="
            page += 1;
            load();
          "
        >
          {{ tr('next') }}
        </button>
      </div>
    </template>
    <h4 class="font-semibold">{{ tr('alerts') }}</h4>
    <p class="text-xs text-n-slate-11">{{ tr('alert_help') }}</p>
    <div
      v-for="row in alerts?.items || []"
      :key="row.id"
      class="grid gap-2 rounded-xl border p-3 text-xs sm:grid-cols-2"
    >
      <span>
        #{{ row.ticket_id }} · {{ row.recipient_name }} · {{ row.channel }}
      </span>
      <span>
        {{ tr(`states.${row.state}`) }} ·
        {{ tr(`reasons.${row.reason || 'queued'}`) }} ({{
          tr('attempts', { count: row.attempts, max: 3 })
        }})
      </span>
      <button
        v-if="row.retryable"
        class="rounded-lg border p-2"
        :disabled="busy"
        @click="
          retrying = row;
          reason = '';
        "
      >
        {{ tr('retry') }}
      </button>
    </div>
    <p
      v-if="alerts && !alerts.total"
      class="text-sm text-n-slate-11"
    >
      {{ tr('empty') }}
    </p>
    <div
      v-if="alerts?.total"
      class="flex justify-between"
    >
      <button
        :disabled="busy || alertPage <= 1"
        @click="
          alertPage -= 1;
          load();
        "
      >
        {{ tr('previous') }}
      </button>
      <span>{{ alertPage }}</span>
      <button
        :disabled="busy || alertPage * 25 >= alerts.total"
        @click="
          alertPage += 1;
          load();
        "
      >
        {{ tr('next') }}
      </button>
    </div>
    <form
      v-if="retrying"
      class="grid gap-2 rounded-xl border border-n-amber-5 bg-n-amber-2 p-4"
      @submit.prevent="retry"
    >
      <label class="grid gap-1 text-sm">
        {{ tr('reason') }}
        <textarea
          v-model="reason"
          rows="2"
          maxlength="2000"
          required
          :disabled="busy"
          class="rounded-lg border bg-n-solid-1 p-2"
        />
      </label>
      <div class="flex gap-2">
        <button
          :disabled="busy || !reason.trim()"
          class="rounded-lg border p-2"
        >
          {{ tr('confirm') }}
        </button>
        <button
          type="button"
          :disabled="busy"
          class="rounded-lg border p-2"
          @click="retrying = null"
        >
          {{ tr('cancel') }}
        </button>
      </div>
    </form>
  </section>
</template>
