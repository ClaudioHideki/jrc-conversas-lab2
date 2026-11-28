<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CrmBadge from '../../components/shared/CrmBadge.vue';
import { formatFunnelMoney, funnelTotals } from './funnelMetrics';
import { exportFunnelDeals } from './exportFunnel';

const props = defineProps({
  selection: { type: Object, required: true },
  report: { type: Object, required: true },
  contextLabels: { type: Array, required: true },
});
const emit = defineEmits(['close']);
const { t, locale } = useI18n();
const dialog = ref(null);
const expanded = ref(false);
const search = ref('');
const stage = ref('');
const owner = ref('');
const page = ref(1);
const perPage = 8;
const stageTones = ['blue', 'green', 'purple', 'purple', 'yellow'];
const stageColors = computed(
  () =>
    new Map(
      props.report.stages.map((stageRow, index) => {
        let color = stageTones[index % stageTones.length];
        if (stageRow.is_won) color = 'green';
        if (stageRow.is_lost) color = 'red';
        return [stageRow.id, color];
      })
    )
);
const stageById = computed(
  () => new Map(props.report.stages.map(item => [item.id, item]))
);
const availableStages = computed(() =>
  props.report.stages.filter(item =>
    props.selection.rows.some(({ deal }) => deal.stage_id === item.id)
  )
);
const owners = computed(() =>
  [
    ...new Map(
      props.selection.rows.map(({ deal }) => [deal.owner_id, deal.owner_name])
    ).entries(),
  ].sort((a, b) => a[1].localeCompare(b[1]))
);
const filtered = computed(() => {
  const term = search.value.trim().toLocaleLowerCase();
  return props.selection.rows.filter(
    ({ deal }) =>
      (!stage.value || stage.value === String(deal.stage_id)) &&
      (!owner.value || owner.value === String(deal.owner_id)) &&
      (!term ||
        [deal.title, deal.company_name, deal.contact_name].some(value =>
          value?.toLocaleLowerCase().includes(term)
        ))
  );
});
const rows = computed(() =>
  filtered.value.slice((page.value - 1) * perPage, page.value * perPage)
);
const totals = computed(() => funnelTotals(filtered.value));
const formatDate = value =>
  value === null || value === undefined
    ? '—'
    : new Intl.DateTimeFormat(locale.value, {
        timeZone: props.report.timezone,
      }).format(value);
const money = (value, currency) =>
  formatFunnelMoney(value, currency, locale.value);
const exportRows = () =>
  exportFunnelDeals(
    filtered.value,
    props.report.stages,
    t,
    formatDate,
    locale.value,
    props.report.month
  );
watch([search, stage, owner], () => {
  page.value = 1;
});
onMounted(() => dialog.value.showModal());
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialog"
      aria-labelledby="funnel-deal-list-title"
      class="m-auto max-h-[calc(100dvh-1.5rem)] w-[96vw] overflow-y-auto rounded-2xl border border-n-weak bg-n-solid-2 p-0 text-n-slate-12 shadow-2xl backdrop:bg-black/40"
      :class="expanded ? 'max-w-none' : 'max-w-6xl'"
      @close="emit('close')"
      @click.self="dialog.close()"
    >
      <div class="min-w-0 space-y-3 p-3 sm:p-5">
        <header class="flex items-start justify-between gap-2">
          <div class="flex min-w-0 items-start gap-2">
            <span
              class="grid size-9 shrink-0 place-items-center rounded-xl bg-n-blue-3 text-n-blue-11 sm:size-11"
            >
              <span class="i-lucide-filter size-5" aria-hidden="true" />
            </span>
            <div>
              <h2
                id="funnel-deal-list-title"
                class="text-lg font-bold sm:text-xl"
              >
                {{ selection.title }}
              </h2>
              <p class="m-0 text-xs text-n-slate-11">
                {{ selection.description }}
              </p>
            </div>
          </div>
          <div class="flex gap-1">
            <button
              type="button"
              class="hidden size-8 place-items-center rounded-lg border border-n-weak !p-0 sm:grid"
              :title="
                expanded
                  ? t('CRM.SALES_FUNNEL.REDUCE')
                  : t('CRM.SALES_FUNNEL.EXPAND')
              "
              :aria-label="
                expanded
                  ? t('CRM.SALES_FUNNEL.REDUCE')
                  : t('CRM.SALES_FUNNEL.EXPAND')
              "
              @click="expanded = !expanded"
            >
              <span
                :class="
                  expanded ? 'i-lucide-minimize-2' : 'i-lucide-maximize-2'
                "
                class="size-4"
                aria-hidden="true"
              />
            </button>
            <button
              type="button"
              class="grid size-8 place-items-center rounded-lg border border-n-weak !p-0"
              :aria-label="t('CRM.SALES_FUNNEL.CLOSE')"
              @click="dialog.close()"
            >
              <span class="i-lucide-x size-4" aria-hidden="true" />
            </button>
          </div>
        </header>
        <ul
          :aria-label="t('CRM.SALES_FUNNEL.FILTER_SCOPE')"
          class="reset-base m-0 flex list-none flex-wrap gap-2 p-0"
        >
          <li
            v-for="label in contextLabels"
            :key="label"
            class="rounded-lg border border-n-weak bg-n-solid-1 px-2.5 py-1.5 text-xs font-medium"
          >
            {{ label }}
          </li>
        </ul>
        <div class="grid gap-2 sm:grid-cols-2">
          <div
            class="flex items-center gap-2 rounded-lg bg-n-blue-3 px-3 py-2.5 text-sm font-bold text-n-blue-11"
          >
            <span
              class="i-lucide-layers-2 size-5 shrink-0"
              aria-hidden="true"
            />
            {{
              t(
                'CRM.SALES_FUNNEL.DEAL_COUNT',
                { count: filtered.length },
                filtered.length
              )
            }}
          </div>
          <div
            class="flex flex-wrap items-center gap-2 rounded-lg bg-n-teal-3 px-3 py-2.5 text-sm font-bold text-n-teal-11"
          >
            <span class="i-lucide-coins size-5 shrink-0" aria-hidden="true" />
            {{ t('CRM.SALES_FUNNEL.TOTAL_VALUE') }}
            <span v-for="[currency, cents] in totals" :key="currency">{{
              money(cents, currency)
            }}</span>
            <span v-if="!totals.length">{{ '—' }}</span>
          </div>
        </div>

        <div class="flex flex-wrap items-center gap-2">
          <label class="relative min-w-[min(100%,14rem)] flex-1">
            <span
              class="i-lucide-search pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-11"
              aria-hidden="true"
            />
            <input
              v-model="search"
              type="search"
              :placeholder="t('CRM.SALES_FUNNEL.TITLE_SEARCH')"
              :aria-label="t('CRM.SALES_FUNNEL.TITLE_SEARCH')"
              class="reset-base m-0 h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 ps-9 pe-3 text-sm"
            />
          </label>
          <select
            v-model="stage"
            :aria-label="t('CRM.SALES_FUNNEL.CURRENT_STAGE')"
            class="!mb-0 h-9 w-auto max-w-full !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none text-sm"
          >
            <option value="">{{ t('CRM.SALES_FUNNEL.CURRENT_STAGE') }}</option>
            <option
              v-for="item in availableStages"
              :key="item.id"
              :value="String(item.id)"
            >
              {{ item.name }}
            </option>
          </select>
          <select
            v-model="owner"
            :aria-label="t('CRM.LIST_LAYOUT.OWNER')"
            class="!mb-0 h-9 w-auto max-w-full !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none text-sm"
          >
            <option value="">{{ t('CRM.LIST_LAYOUT.OWNER') }}</option>
            <option v-for="[id, name] in owners" :key="id" :value="String(id)">
              {{ name }}
            </option>
          </select>
          <button
            type="button"
            class="inline-flex items-center gap-1 rounded-lg border border-n-blue-6 bg-n-blue-2 px-3 py-1.5 text-xs font-semibold text-n-blue-11"
            :disabled="!filtered.length"
            @click="exportRows"
          >
            <span class="i-lucide-download size-4" aria-hidden="true" />
            {{ t('CRM.SALES_FUNNEL.EXPORT') }}
          </button>
        </div>
        <div class="relative overflow-x-auto rounded-lg border border-n-weak">
          <table class="w-full min-w-[740px] text-left text-sm">
            <thead class="bg-n-blue-2 text-xs text-n-slate-11">
              <tr>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.DEAL_NAME') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.SALES_FUNNEL.ENTRY_DATE') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.SALES_FUNNEL.CURRENT_STAGE') }}
                </th>
                <th v-if="selection.measured" scope="col" class="px-3 py-2">
                  {{ t('CRM.SALES_FUNNEL.RECORDED_TIME') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.VALUE') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.OWNER') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.CONTACT_LEAD.UI.ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr
                v-for="{ deal, enteredAt, days } in rows"
                :key="deal.id"
                class="hover:bg-n-blue-2"
              >
                <td class="min-w-40 px-3 py-1.5">
                  <p class="m-0 font-semibold">{{ deal.title }}</p>
                  <p
                    v-if="deal.company_name || deal.contact_name"
                    class="m-0 text-xs text-n-slate-11"
                  >
                    {{ deal.company_name || deal.contact_name }}
                  </p>
                </td>
                <td class="whitespace-nowrap px-3 py-1.5 text-xs">
                  {{ formatDate(enteredAt) }}
                </td>
                <td class="px-3 py-1.5">
                  <CrmBadge :color="stageColors.get(deal.stage_id) || 'gray'">{{
                    stageById.get(deal.stage_id)?.name || '—'
                  }}</CrmBadge>
                </td>
                <td
                  v-if="selection.measured"
                  class="whitespace-nowrap px-3 py-1.5 text-xs"
                >
                  {{
                    t('CRM.SALES_FUNNEL.DAYS', {
                      count: Math.round(days * 10) / 10,
                    })
                  }}
                </td>
                <td class="whitespace-nowrap px-3 py-1.5 text-xs font-semibold">
                  {{ money(deal.value_cents, deal.currency) }}
                </td>
                <td class="px-3 py-1.5">
                  <span
                    class="flex items-center gap-1.5 whitespace-nowrap text-xs"
                  >
                    <Avatar :name="deal.owner_name" :size="22" rounded-full />
                    {{ deal.owner_name }}
                  </span>
                </td>
                <td class="px-3 py-1.5">
                  <RouterLink
                    :to="{ name: 'crm_deals', query: { dealId: deal.id } }"
                    class="inline-flex items-center gap-1 rounded-md border border-n-blue-6 bg-n-blue-2 px-2 py-1 text-xs font-semibold text-n-blue-11"
                  >
                    <span
                      class="i-lucide-external-link size-3.5"
                      aria-hidden="true"
                    />
                    {{ t('CRM.LIST_LAYOUT.OPEN') }}
                  </RouterLink>
                </td>
              </tr>
              <tr v-if="!rows.length">
                <td
                  :colspan="selection.measured ? 7 : 6"
                  class="px-3 py-8 text-center text-sm text-n-slate-11"
                >
                  {{ t('CRM.SALES_FUNNEL.NO_FILTERED_ROWS') }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <footer
          class="flex flex-wrap items-center justify-end gap-2 sm:flex-nowrap"
        >
          <PaginationFooter
            v-if="filtered.length"
            :current-page="page"
            :total-items="filtered.length"
            :items-per-page="perPage"
            current-page-info="CRM.SALES_FUNNEL.SHOWING"
            numbered
            class="!border-t-0 !p-0"
            @update:current-page="page = $event"
          />
          <button
            type="button"
            class="rounded-lg border border-n-weak px-3 py-1.5 text-xs font-semibold"
            @click="dialog.close()"
          >
            {{ t('CRM.SALES_FUNNEL.CLOSE') }}
          </button>
        </footer>
      </div>
    </dialog>
  </TeleportWithDirection>
</template>
