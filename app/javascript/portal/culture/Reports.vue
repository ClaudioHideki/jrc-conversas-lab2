<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { filterQuery, formatDate, request } from './client';

const props = defineProps({
  base: { type: String, required: true },
  setup: { type: Object, required: true },
  section: { type: String, required: true },
});
const emit = defineEmits(['expired']);
const { t } = useI18n();
const filters = reactive({
  company_id: '',
  unit_id: '',
  department: '',
  culture_person_query: '',
  from: '',
  to: '',
  version_id: '',
});
const state = computed(
  () => ({ confirmations: 'confirmed', pendings: 'pending' })[props.section]
);
const report = ref(null);
const error = ref('');
const busy = ref(false);
const input = 'min-w-0 rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2';
const buttons =
  'rounded-lg border border-n-weak px-3 py-2 text-sm font-medium hover:bg-n-solid-3 disabled:opacity-50';
const companies = computed(() => [
  ...new Map(
    props.setup.units.map(unit => [unit.company_id, unit.company])
  ).entries(),
]);
const units = computed(() =>
  props.setup.units.filter(
    unit => !filters.company_id || unit.company_id === filters.company_id
  )
);
const query = page => filterQuery({ ...filters, state: state.value, page });

async function load(page = 1) {
  if (busy.value) return;
  busy.value = true;
  error.value = '';
  try {
    report.value = await request(`${props.base}/admin/report?${query(page)}`);
  } catch (failure) {
    if (failure.status === 401) emit('expired');
    else error.value = 'error';
  } finally {
    busy.value = false;
  }
}

function changeCompany() {
  filters.unit_id = '';
}

onMounted(() => load());
</script>

<template>
  <div class="grid gap-4">
    <form
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 sm:grid-cols-2 lg:grid-cols-4"
      @submit.prevent="load()"
    >
      <label class="grid gap-1 text-sm">
        {{ t('company') }}
        <select
          v-model="filters.company_id"
          :class="input"
          @change="changeCompany"
        >
          <option value="">{{ t('all') }}</option>
          <option v-for="[id, name] in companies" :key="id" :value="id">
            {{ name }}
          </option>
        </select>
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('unit') }}
        <select v-model="filters.unit_id" :class="input">
          <option value="">{{ t('all') }}</option>
          <option v-for="unit in units" :key="unit.id" :value="unit.id">
            {{ unit.name }}
          </option>
        </select>
      </label>
      <label class="grid gap-1 text-sm">
        {{ t('version') }}
        <select v-model="filters.version_id" :class="input">
          <option value="">{{ t('current') }}</option>
          <option
            v-for="item in setup.versions"
            :key="item.id"
            :value="item.id"
          >
            {{ item.title }} · {{ item.number }}
          </option>
        </select>
      </label>
      <label
        v-for="[key, label, type] in [
          ['department', 'sector', 'text'],
          ['culture_person_query', 'person', 'search'],
          ['from', 'date_from', 'date'],
          ['to', 'date_to', 'date'],
        ]"
        :key="key"
        class="grid gap-1 text-sm"
      >
        {{ t(label) }}
        <input v-model="filters[key]" :type="type" :class="input" />
      </label>
      <div class="flex flex-wrap items-end gap-2">
        <button
          class="rounded-lg bg-blue-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
          :disabled="busy"
        >
          {{ t(busy ? 'loading' : 'search') }}
        </button>
      </div>
      <div class="flex flex-wrap gap-2 sm:col-span-2 lg:col-span-4">
        <a
          :class="buttons"
          :href="`${base}/admin/export?type=xlsx&${query()}`"
          >{{ t('export_xlsx') }}</a
        >
        <a
          :class="buttons"
          :href="`${base}/admin/export?type=pdf&${query()}`"
          >{{ t('export_pdf') }}</a
        >
      </div>
    </form>
    <p v-if="error" class="text-n-ruby-11" role="alert">{{ t(error) }}</p>
    <template v-if="report">
      <div
        v-if="section === 'overview'"
        class="grid grid-cols-2 gap-3 lg:grid-cols-4"
      >
        <article
          v-for="[label, value] in [
            ['eligible', report.summary.total],
            ['confirmations', report.summary.confirmed],
            ['pendings', report.summary.pending],
            ['percentage', `${report.summary.percentage}%`],
          ]"
          :key="label"
          class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
        >
          <p class="text-sm text-n-slate-11">{{ t(label) }}</p>
          <p class="mt-2 text-2xl font-bold text-n-blue-11">{{ value }}</p>
        </article>
      </div>
      <div v-if="section === 'overview'" class="grid gap-3 lg:grid-cols-2">
        <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <h3 class="font-semibold">{{ t('recent') }}</h3>
          <ul v-if="report.recent.length" class="mt-3 divide-y divide-n-weak">
            <li v-for="entry in report.recent" :key="entry.id" class="py-2">
              <span class="font-medium">{{
                entry.collaborator || entry.user_id
              }}</span>
              <p class="text-sm text-n-slate-11">
                {{ entry.title }} ·
                {{ t('published', { number: entry.version }) }} ·
                {{ formatDate(entry.confirmed_at) }}
              </p>
            </li>
          </ul>
          <p v-else class="mt-3 text-n-slate-11">{{ t('report_empty') }}</p>
        </section>
        <section class="rounded-xl border border-n-weak bg-n-solid-1 p-4">
          <h3 class="font-semibold">{{ t('distribution') }}</h3>
          <ul class="mt-3 divide-y divide-n-weak">
            <li
              v-for="item in report.summary.distribution"
              :key="`${item.unit_id}:${item.department}`"
              class="flex justify-between gap-3 py-2 text-sm"
            >
              <span
                >{{ item.company }} · {{ item.unit }} ·
                {{ item.department || t('no_info') }}</span
              >
              <span class="shrink-0 font-medium"
                >{{ item.confirmed }} / {{ item.total }}</span
              >
            </li>
          </ul>
          <p v-if="!report.summary.distribution.length" class="text-n-slate-11">
            {{ t('empty') }}
          </p>
        </section>
      </div>
      <div class="overflow-x-auto rounded-xl border border-n-weak bg-n-solid-1">
        <table class="w-full text-left text-sm">
          <thead class="bg-n-solid-3">
            <tr>
              <th
                v-for="header in [
                  'person',
                  'company',
                  'unit',
                  'sector',
                  'version',
                  'state',
                  'timestamp',
                ]"
                :key="header"
                scope="col"
                class="whitespace-nowrap px-3 py-3"
              >
                {{ t(header) }}
              </th>
            </tr>
          </thead>
          <tbody class="divide-y divide-n-weak">
            <tr v-for="entry in report.rows" :key="entry.id">
              <td class="min-w-36 px-3 py-2 font-medium">
                {{ entry.collaborator || entry.user_id }}
              </td>
              <td class="min-w-32 px-3 py-2">{{ entry.company }}</td>
              <td class="min-w-28 px-3 py-2">{{ entry.unit }}</td>
              <td class="px-3 py-2">{{ entry.department || t('no_info') }}</td>
              <td class="min-w-32 px-3 py-2">
                {{ entry.title }} · {{ entry.version }}
              </td>
              <td
                class="whitespace-nowrap px-3 py-2"
                :class="
                  entry.confirmed_at ? 'text-n-teal-11' : 'text-n-amber-11'
                "
              >
                {{ t(entry.confirmed_at ? 'confirmed' : 'pending') }}
              </td>
              <td class="whitespace-nowrap px-3 py-2">
                {{ formatDate(entry.confirmed_at) }}
              </td>
            </tr>
            <tr v-if="!report.rows.length">
              <td colspan="7" class="p-4 text-n-slate-11">{{ t('empty') }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div
        v-if="report.pages > 1"
        class="flex flex-wrap items-center gap-2 text-sm"
      >
        <button
          :class="buttons"
          :disabled="report.page === 1 || busy"
          @click="load(report.page - 1)"
        >
          {{ t('previous') }}
        </button>
        <span>{{ t('pages', report) }}</span>
        <button
          :class="buttons"
          :disabled="report.page === report.pages || busy"
          @click="load(report.page + 1)"
        >
          {{ t('next') }}
        </button>
      </div>
    </template>
  </div>
</template>
