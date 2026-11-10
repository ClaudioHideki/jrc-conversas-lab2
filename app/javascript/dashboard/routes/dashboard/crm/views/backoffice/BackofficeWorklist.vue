<script setup>
import BackofficeCustomerPicker from './BackofficeCustomerPicker.vue';
import { useRoute } from 'vue-router';
import { useBackofficeWorkspace } from './useBackofficeWorkspace';
import {
  stages,
  statuses,
  priorities,
  kinds,
  useBackofficePresentation,
} from './useBackofficePresentation';

const props = defineProps({
  mine: { type: Boolean, default: false },
  section: { type: String, default: 'requests' },
});
const route = useRoute();
const { text, label, date, late, destination, deadline, slaLabel } =
  useBackofficePresentation();
let initialStatus = 'active';
if (statuses.includes(route.query.status)) initialStatus = route.query.status;
if (route.query.status === 'all') initialStatus = '';
const { filters, result, options, loading, error, load } =
  useBackofficeWorkspace(props.mine ? 'mine' : props.section, {
    stage: stages.includes(route.query.stage) ? route.query.stage : '',
    company_id: route.query.companyId || '',
    status: initialStatus,
    operations_queue_id: route.query.queueId || '',
    overdue: route.query.overdue === 'true' ? 'true' : '',
  });
const openRequest = id => ({
  ...destination(id),
  query: {
    customer_segment_id: route.query.customer_segment_id,
    tab:
      {
        docs: 'documents',
        implement: 'checklist',
        provision: 'checklist',
        issues: 'issues',
        finance: 'finance',
      }[props.section] || 'operations',
  },
});
const optionGroups = ['operations_queue_id', 'owner_id', 'business_unit_id'];
const optionSources = {
  operations_queue_id: 'queues',
  owner_id: 'owners',
  business_unit_id: 'business_units',
};
</script>

<template>
  <div
    class="space-y-4"
    :aria-busy="loading"
  >
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-xl font-bold">
          {{ text(`NAV.${section}`) }}
        </h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ text(mine ? 'MINE_NOTE' : 'SCOPE_NOTE') }}
        </p>
      </div>
      <button
        class="rounded-lg border bg-n-solid-2 px-4 py-2 text-sm font-semibold disabled:opacity-50"
        :disabled="loading"
        @click="load()"
      >
        {{ text('REFRESH') }}
      </button>
    </div>
    <form
      class="grid gap-3 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm sm:grid-cols-2 xl:grid-cols-4"
      @submit.prevent="load(1)"
    >
      <label class="text-xs font-semibold">
        {{ text('SEARCH') }}
        <input
          v-model="filters.q"
          name="q"
          maxlength="200"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
          :placeholder="text('SEARCH_HINT')"
        />
      </label>
      <label class="text-xs font-semibold">
        {{ text('STATUS') }}
        <select
          v-model="filters.status"
          name="status"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
        >
          <option value="">{{ text('ALL') }}</option>
          <option value="active">{{ text('METRICS.active') }}</option>
          <option
            v-for="value in statuses"
            :key="value"
            :value="value"
          >
            {{ label(value) }}
          </option>
        </select>
      </label>
      <BackofficeCustomerPicker
        v-model="filters.company_id"
        class="sm:col-span-2"
      />

      <div class="flex flex-wrap items-start gap-3 sm:col-span-2 xl:col-span-4">
        <details class="min-w-0 flex-1">
          <summary
            class="cursor-pointer text-sm font-semibold text-emerald-700"
          >
            {{ text('ADVANCED_FILTERS') }}
          </summary>
          <div class="mt-3 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <label class="text-xs font-semibold">
              {{ text('STAGE') }}
              <select
                v-model="filters.stage"
                name="stage"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
              >
                <option value="">{{ text('ALL') }}</option>
                <option
                  v-for="value in stages"
                  :key="value"
                  :value="value"
                >
                  {{ label(value) }}
                </option>
              </select>
            </label>
            <label class="text-xs font-semibold">
              {{ text('PRIORITY') }}
              <select
                v-model="filters.priority"
                name="priority"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
              >
                <option value="">{{ text('ALL') }}</option>
                <option
                  v-for="value in priorities"
                  :key="value"
                  :value="value"
                >
                  {{ label(value) }}
                </option>
              </select>
            </label>
            <label class="text-xs font-semibold">
              {{ text('KIND') }}
              <select
                v-model="filters.kind"
                name="kind"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
              >
                <option value="">{{ text('ALL') }}</option>
                <option
                  v-for="value in kinds"
                  :key="value"
                  :value="value"
                >
                  {{ label(value) }}
                </option>
              </select>
            </label>
            <label
              v-for="key in optionGroups.filter(
                item => !mine || item !== 'owner_id'
              )"
              :key="key"
              class="text-xs font-semibold"
            >
              {{ text(`FILTERS.${key}`) }}
              <select
                v-model="filters[key]"
                :name="key"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
              >
                <option value="">{{ text('ALL') }}</option>
                <option
                  v-for="option in options[optionSources[key]]"
                  :key="option.id"
                  :value="option.id"
                >
                  {{ option.name }}
                </option>
              </select>
            </label>
            <label class="text-xs font-semibold">
              {{ text('SORT') }}
              <select
                v-model="filters.sort"
                name="sort"
                class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-sm"
              >
                <option
                  v-for="value in ['recent', 'oldest', 'deadline', 'priority']"
                  :key="value"
                  :value="value"
                >
                  {{ text(`SORTS.${value}`) }}
                </option>
              </select>
            </label>
          </div>
        </details>
        <label class="flex items-center gap-2 text-sm">
          <input
            v-model="filters.overdue"
            type="checkbox"
            true-value="true"
            false-value=""
          />
          {{ text('ONLY_OVERDUE') }}
        </label>
        <button
          type="submit"
          class="ml-auto rounded-lg bg-emerald-600 px-5 py-2 text-sm font-semibold text-white disabled:opacity-50"
          :disabled="loading"
        >
          {{ text('APPLY') }}
        </button>
      </div>
    </form>
    <p
      v-if="loading"
      role="status"
      class="rounded-xl border bg-n-solid-2 p-8"
    >
      {{ text('LOADING') }}
    </p>
    <p
      v-else-if="error"
      role="alert"
      class="rounded-xl border border-red-200 bg-red-50 p-5 text-red-700"
    >
      {{ text('LOAD_ERROR') }}
    </p>
    <template v-else-if="result">
      <div class="grid gap-3 sm:grid-cols-3">
        <article
          v-for="key in ['total', 'overdue', 'blocked']"
          :key="key"
          class="flex items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2"
        >
          <p class="text-xs text-n-slate-11">{{ text(`METRICS.${key}`) }}</p>
          <b class="text-xl">{{ result.summary[key] }}</b>
        </article>
      </div>
      <section
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <div
          v-if="mine"
          class="grid gap-4 p-4 2xl:grid-cols-2"
        >
          <RouterLink
            v-for="item in result.data"
            :key="item.id"
            :to="openRequest(item.id)"
            class="rounded-xl border border-n-weak border-l-4 p-4 transition hover:border-emerald-400"
            :class="
              late(item)
                ? 'border-l-red-500'
                : item.status === 'blocked'
                  ? 'border-l-amber-500'
                  : 'border-l-emerald-500'
            "
          >
            <div class="flex items-center justify-between gap-3">
              <b class="text-xs text-emerald-700">{{ item.request_number }}</b>
              <span class="rounded-lg bg-n-slate-3 px-2 py-1 text-xs">
                {{ label(item.priority) }}
              </span>
            </div>
            <h3 class="mt-2 font-bold">{{ item.title }}</h3>
            <p class="mt-1 text-sm text-n-slate-11">
              {{
                item.company?.name || item.contact?.name || text('NO_CLIENT')
              }}
              <span
                v-if="item.company && item.contact"
                class="block text-xs text-n-slate-11"
              >
                {{ item.contact.name }}
              </span>
            </p>
            <dl class="mt-4 grid grid-cols-2 gap-3 text-sm">
              <div>
                <dt class="text-xs text-n-slate-11">{{ text('STAGE') }}</dt>
                <dd class="font-semibold">{{ label(item.stage) }}</dd>
              </div>
              <div>
                <dt class="text-xs text-n-slate-11">{{ text('STATUS') }}</dt>
                <dd>{{ label(item.status) }}</dd>
              </div>
              <div>
                <dt class="text-xs text-n-slate-11">
                  {{ text('FILTERS.operations_queue_id') }}
                </dt>
                <dd>{{ item.queue?.name || text('NO_QUEUE') }}</dd>
              </div>
              <div :class="{ 'text-red-700': late(item) }">
                <dt class="text-xs">{{ text('DEADLINE') }}</dt>
                <dd>{{ date(deadline(item)) }}</dd>
              </div>
            </dl>
            <span
              class="mt-4 inline-block rounded-lg bg-emerald-50 px-3 py-2 text-sm font-semibold text-emerald-800"
            >
              {{ text('OPEN_OPERATION') }}
            </span>
          </RouterLink>
          <p
            v-if="!result.data.length"
            class="p-6 text-center text-sm text-n-slate-11"
          >
            {{ text('EMPTY') }}
          </p>
        </div>
        <div
          v-else
          class="overflow-x-auto"
        >
          <table class="w-full min-w-[800px] text-left text-sm">
            <thead class="bg-n-slate-3 text-xs text-n-slate-11">
              <tr>
                <th
                  v-for="key in [
                    'REQUEST',
                    'CLIENT',
                    'STAGE',
                    'STATUS',
                    'PRIORITY',
                    'QUEUE_OWNER',
                    'DEADLINE',
                  ]"
                  :key="key"
                  scope="col"
                  class="p-3"
                >
                  {{ text(key) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="item in result.data"
                :key="item.id"
                class="border-t border-n-weak hover:bg-n-slate-2"
              >
                <td class="max-w-[260px] p-3">
                  <RouterLink
                    :to="openRequest(item.id)"
                    class="font-semibold text-emerald-700 underline-offset-2 hover:underline"
                  >
                    {{ item.request_number }}
                  </RouterLink>
                  <p class="mt-1 truncate">{{ item.title }}</p>
                  <p class="mt-1 text-xs text-n-slate-11">
                    {{ item.order.order_number }}
                  </p>
                </td>
                <td class="p-3">
                  {{
                    item.company?.name ||
                    item.contact?.name ||
                    text('NO_CLIENT')
                  }}
                  <span
                    v-if="item.company && item.contact"
                    class="block text-xs text-n-slate-11"
                  >
                    {{ item.contact.name }}
                  </span>
                </td>
                <td class="p-3">{{ label(item.stage) }}</td>
                <td class="p-3">
                  <span
                    class="whitespace-nowrap rounded-lg px-2 py-1 text-xs"
                    :class="
                      item.status === 'blocked'
                        ? 'bg-amber-100 text-amber-900'
                        : 'bg-n-slate-3'
                    "
                  >
                    {{ label(item.status) }}
                  </span>
                </td>
                <td
                  class="p-3"
                  :class="{
                    'font-bold text-red-700': item.priority === 'critical',
                  }"
                >
                  {{ label(item.priority) }}
                </td>
                <td class="p-3">
                  <p>{{ item.queue?.name || text('NO_QUEUE') }}</p>
                  <p class="mt-1 text-xs text-n-slate-11">
                    {{ item.owner.name }}
                  </p>
                </td>
                <td
                  class="p-3"
                  :class="{ 'font-semibold text-red-700': late(item) }"
                >
                  <p>{{ date(deadline(item)) }}</p>
                  <p class="mt-1 text-xs">
                    {{ late(item) ? label('overdue') : slaLabel(item.sla) }}
                  </p>
                </td>
              </tr>
            </tbody>
          </table>
          <p
            v-if="!result.data.length"
            class="p-10 text-center text-sm text-n-slate-11"
          >
            {{ text('EMPTY') }}
          </p>
        </div>
        <footer
          class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak p-4"
        >
          <p class="text-sm text-n-slate-11">
            {{ text('PAGE') }} {{ result.meta.page }}
            {{ text('PAGE_SEPARATOR') }} {{ result.meta.pages }}
            {{ text('SEPARATOR') }} {{ result.meta.total }}
            {{ text('RESULTS') }}
          </p>
          <div class="flex gap-2">
            <button
              class="rounded-lg border px-3 py-2 text-sm disabled:opacity-40"
              :disabled="result.meta.page <= 1"
              @click="load(result.meta.page - 1)"
            >
              {{ text('PREVIOUS') }}
            </button>
            <button
              class="rounded-lg bg-emerald-600 px-3 py-2 text-sm font-semibold text-white disabled:opacity-40"
              :disabled="result.meta.page >= result.meta.pages"
              @click="load(result.meta.page + 1)"
            >
              {{ text('NEXT') }}
            </button>
          </div>
        </footer>
      </section>
    </template>
  </div>
</template>
