<script setup>
import { onBeforeUnmount, onMounted, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/serviceDeskReportExports';
import { useOperationalScope } from '../composables/useOperationalScope';
import { assertEnvelope, reportFilters } from '../helpers/operationalRules.mjs';
import { canonicalId } from '../helpers/access';
const props = defineProps({
  unitId: { type: String, required: true },
  filters: { type: Object, required: true },
  total: { type: Number, required: true },
  limits: { type: Object, default: () => ({}) },
});
const { t, locale } = useI18n();
const scope = useOperationalScope(
  toRef(props, 'unitId'),
  context => context?.capabilities?.operational_reports?.export === true
);
const formats = ['csv_summary', 'csv_detailed', 'xlsx', 'pdf'];
const formatLimit = value =>
  new Intl.NumberFormat(locale.value.replace('_', '-')).format(value);
const expanded = ref(false);
const section = ref(null);
const jobs = ref([]);
const busy = ref(false);
const error = ref('');
let timer;
const validate = (row, lease) => {
  assertEnvelope(row, lease.context, lease.unit);
  if (
    !canonicalId(row.id) ||
    !formats.includes(row.format) ||
    !['queued', 'processing', 'ready', 'failed', 'expired'].includes(row.state)
  )
    throw new TypeError('Invalid export result');
  return row;
};
const refresh = async () => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  try {
    const payload = assertEnvelope(
      await API.list(lease.context.account_id, lease.unit, lease.signal),
      lease.context,
      lease.unit
    );
    if (!scope.live(lease)) return;
    if (!Array.isArray(payload.items)) throw new TypeError('Invalid exports');
    jobs.value = payload.items.map(row => validate(row, lease));
    if (jobs.value.some(row => ['queued', 'processing'].includes(row.state)))
      timer = window.setTimeout(refresh, 3000);
  } catch {
    if (scope.live(lease)) error.value = 'unavailable';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
const create = async format => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  error.value = '';
  window.clearTimeout(timer);
  try {
    const filters = { ...reportFilters(props.filters), unit_id: lease.unit };
    const row = validate(
      await API.create(
        lease.context.account_id,
        { format, filters, expected_count: props.total },
        lease.signal
      ),
      lease
    );
    if (!scope.live(lease)) return;
    jobs.value = [row, ...jobs.value.filter(item => item.id !== row.id)].slice(
      0,
      20
    );
    timer = window.setTimeout(refresh, 1500);
  } catch (failure) {
    if (scope.live(lease))
      error.value =
        failure?.response?.status === 409 ? 'report_changed' : 'unavailable';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
const download = async row => {
  if (busy.value) return;
  const lease = scope.begin();
  if (!lease) return;
  busy.value = true;
  error.value = '';
  try {
    const blob = await API.download(
      lease.context.account_id,
      row.id,
      lease.signal
    );
    if (!scope.live(lease)) return;
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = String(row.filename || 'JRC_ServiceDesk').replace(
      /[\\/\r\n\0]/g,
      '_'
    );
    link.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch {
    if (scope.live(lease)) error.value = 'access_changed';
  } finally {
    if (scope.live(lease)) busy.value = false;
  }
};
watch(
  [scope.identity, () => props.unitId],
  () => {
    window.clearTimeout(timer);
    jobs.value = [];
    busy.value = false;
    error.value = '';
    expanded.value = false;
  },
  { flush: 'sync' }
);
onMounted(refresh);
onBeforeUnmount(() => window.clearTimeout(timer));
const openMenu = () => {
  expanded.value = true;
  section.value?.scrollIntoView?.({ block: 'nearest' });
};
defineExpose({ openMenu });
</script>

<template>
  <section
    ref="section"
    class="rounded-2xl border border-blue-200 bg-blue-50/70 p-4 dark:border-n-weak dark:bg-n-solid-2"
    data-testid="report-export-menu"
  >
    <button
      type="button"
      class="flex items-center gap-2 font-semibold text-n-blue-11"
      :aria-expanded="expanded"
      @click="expanded = !expanded"
    >
      <span aria-hidden="true" class="i-lucide-download size-5" />{{
        t('JRC_SERVICE_DESK.EXPORT_FILES.title')
      }}
      <span
        :class="expanded ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
        class="size-4"
      />
    </button>
    <div v-if="expanded" class="mt-4 grid gap-4">
      <p class="m-0 text-sm">
        {{ t('JRC_SERVICE_DESK.EXPORT_FILES.help', { count: total }) }}
      </p>
      <div class="grid gap-2 sm:grid-cols-2 xl:grid-cols-4">
        <button
          v-for="format in formats"
          :key="format"
          type="button"
          :disabled="
            busy ||
            !scope.allowed.value ||
            (limits[format] && total > limits[format])
          "
          class="rounded-xl border border-blue-200 bg-n-solid-1 p-3 text-start text-sm font-semibold text-n-blue-11 shadow-sm hover:bg-blue-100 disabled:opacity-50 dark:border-n-weak dark:hover:bg-n-solid-3"
          @click="create(format)"
        >
          {{ t(`JRC_SERVICE_DESK.EXPORT_FILES.formats.${format}`) }}
          <span
            v-if="limits[format]"
            class="mt-1 block text-xs font-normal text-n-slate-11"
            >{{
              t('JRC_SERVICE_DESK.EXPORT_FILES.limit', {
                limit: formatLimit(limits[format]),
              })
            }}</span
          >
        </button>
      </div>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.EXPORT_FILES.narrow') }}
      </p>
      <p class="m-0 rounded-lg border border-blue-200 bg-n-solid-1 p-3 text-sm">
        {{ t('JRC_SERVICE_DESK.EXPORT_FILES.schedule_later') }}
      </p>
      <p v-if="error" role="alert" class="m-0 text-sm text-n-ruby-11">
        {{ t(`JRC_SERVICE_DESK.EXPORT_FILES.errors.${error}`) }}
      </p>
      <div class="flex items-center justify-between gap-2">
        <h4 class="m-0 text-sm font-semibold">
          {{ t('JRC_SERVICE_DESK.EXPORT_FILES.history') }}
        </h4>
        <button
          type="button"
          class="text-sm text-n-blue-11"
          :disabled="busy"
          @click="refresh"
        >
          {{ t('JRC_SERVICE_DESK.COMMON.retry') }}
        </button>
      </div>
      <ul class="m-0 grid list-none gap-2 p-0" aria-live="polite">
        <li
          v-for="row in jobs"
          :key="row.id"
          class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-100 bg-n-solid-1 p-3 dark:border-n-weak"
        >
          <div class="min-w-0">
            <strong class="text-sm"
              >{{ t(`JRC_SERVICE_DESK.EXPORT_FILES.formats.${row.format}`) }} ·
              #{{ row.id }}</strong
            >
            <p class="m-0 break-all text-xs text-n-slate-11">
              {{
                row.filename ||
                t(`JRC_SERVICE_DESK.EXPORT_FILES.states.${row.state}`)
              }}
            </p>
            <p v-if="row.state === 'failed'" class="m-0 text-xs text-n-ruby-11">
              {{
                t(
                  `JRC_SERVICE_DESK.EXPORT_FILES.errors.${row.error_code || 'unavailable'}`
                )
              }}
            </p>
          </div>
          <button
            v-if="row.state === 'ready'"
            type="button"
            :disabled="busy"
            class="rounded-lg bg-blue-600 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
            @click="download(row)"
          >
            {{ t('JRC_SERVICE_DESK.EXPORT_FILES.download') }}
          </button>
          <span
            v-else
            class="rounded-lg bg-blue-100 px-2 py-1 text-xs text-blue-900"
            >{{ t(`JRC_SERVICE_DESK.EXPORT_FILES.states.${row.state}`) }}</span
          >
        </li>
      </ul>
      <p class="m-0 text-xs text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.EXPORT_FILES.retention') }}
      </p>
    </div>
  </section>
</template>
