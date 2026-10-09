<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
const props = defineProps({
  policy: { type: Object, required: true },
  options: { type: Object, default: () => ({}) },
  busy: Boolean,
});
const emit = defineEmits(['change']);
const { t } = useI18n();
const localTime = date =>
  new Date(date - new Date(date).getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
const from = ref(localTime(Date.now() - 30 * 86400000));
const until = ref('');
const units = ref([]);
const companies = ref([]);
const operators = ref([]);
const choices = (kind, field) =>
  (props.options[kind] || []).filter(item =>
    props.policy.definition?.[field]?.includes(Number(item.id))
  );
const settings = computed(() => {
  const start = Date.parse(from.value);
  const end = until.value ? Date.parse(until.value) : Date.now();
  const valid =
    Number.isFinite(start) &&
    Number.isFinite(end) &&
    start < end &&
    end - start <= 366 * 86400000;
  const filters = {};
  if (units.value.length) filters.unit_ids = [...units.value];
  if (companies.value.length) filters.company_ids = [...companies.value];
  if (operators.value.length)
    filters.assignee_account_user_ids = [...operators.value];
  return {
    valid,
    from: valid ? new Date(start).toISOString() : null,
    ...(until.value && valid ? { until: new Date(end).toISOString() } : {}),
    filters,
  };
});
watch(settings, result => emit('change', result), { immediate: true });
</script>

<template>
  <details
    class="mt-3 rounded border border-n-weak p-3"
    data-testid="helpdesk-report-filters"
  >
    <summary>{{ t('JRC_NICO_HELPDESK.REPORT_FILTERS') }}</summary>
    <p class="mt-2 text-xs text-n-slate-11">
      {{ t('JRC_NICO_HELPDESK.REPORT_FILTER_SCOPE') }}
    </p>
    <div class="mt-3 grid gap-3 text-sm md:grid-cols-2">
      <label
        >{{ t('JRC_NICO_HELPDESK.KPI_FROM')
        }}<input
          v-model="from"
          :disabled="busy"
          type="datetime-local"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-kpi-from"
      /></label>
      <label
        >{{ t('JRC_NICO_HELPDESK.KPI_UNTIL')
        }}<input
          v-model="until"
          :disabled="busy"
          type="datetime-local"
          class="mt-1 block w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-kpi-until"
      /></label>
      <label v-if="choices('units', 'unit_ids').length"
        >{{ t('JRC_NICO_HELPDESK.UNITS')
        }}<select
          v-model="units"
          :disabled="busy"
          multiple
          class="mt-1 block min-h-20 w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-filter-units"
        >
          <option
            v-for="item in choices('units', 'unit_ids')"
            :key="item.id"
            :value="Number(item.id)"
          >
            {{ item.name }}
          </option>
        </select></label
      >
      <label v-if="choices('companies', 'company_ids').length"
        >{{ t('JRC_NICO_HELPDESK.COMPANIES')
        }}<select
          v-model="companies"
          :disabled="busy"
          multiple
          class="mt-1 block min-h-20 w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-filter-companies"
        >
          <option
            v-for="item in choices('companies', 'company_ids')"
            :key="item.id"
            :value="Number(item.id)"
          >
            {{ item.name }}
          </option>
        </select></label
      >
      <label v-if="choices('operators', 'operator_ids').length"
        >{{ t('JRC_NICO_HELPDESK.OPERATORS')
        }}<select
          v-model="operators"
          :disabled="busy"
          multiple
          class="mt-1 block min-h-20 w-full rounded border border-n-weak bg-n-background p-2"
          data-testid="helpdesk-filter-operators"
        >
          <option
            v-for="item in choices('operators', 'operator_ids')"
            :key="item.id"
            :value="Number(item.id)"
          >
            {{ item.name }}
          </option>
        </select></label
      >
    </div>
    <p v-if="!settings.valid" role="alert" class="mt-2 text-xs text-n-ruby-11">
      {{ t('JRC_NICO_HELPDESK.REPORT_INTERVAL_INVALID') }}
    </p>
  </details>
</template>
