<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePolicy } from 'dashboard/composables/usePolicy';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import CompanyEditorDialog from './components/CompanyEditorDialog.vue';
import CompanyDetailsDialog from './components/CompanyDetailsDialog.vue';
import DirectoryMetrics from './components/DirectoryMetrics.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcCustomers';
import { useCompanyDirectory } from './useCompanyDirectory';
import { useCustomerMaster } from './useCustomerMaster';
import {
  T,
  FIELD_LABELS,
  RELATIONSHIPS,
  inputClass,
  buttonClass,
  primaryClass,
} from './copy';

const { t } = useI18n();
const { checkPermissions } = usePolicy();
const { accountId, accountScopedRoute, canAdmin } = useCustomerMaster();
const {
  identity,
  rows,
  metadata,
  meta,
  page,
  error,
  busy,
  creating,
  selection,
  filters,
  search,
  changePage,
  closeEditor,
  saved,
  load,
} = useCompanyDirectory();
const moreFilters = ref(false);
const editingCompany = ref(null);
const deletingCompany = ref(null);
const deleteDialog = ref(null);
const deleting = ref(false);
const deleteError = ref('');
watch(identity, () => {
  editingCompany.value = null;
  deletingCompany.value = null;
  deleting.value = false;
  deleteError.value = '';
});

const confirmCompanyDelete = async company => {
  if (!canAdmin.value || deleting.value) return;
  deletingCompany.value = company;
  deleteError.value = '';
  await nextTick();
  deleteDialog.value?.open();
};
const deleteCompany = async () => {
  const company = deletingCompany.value;
  if (!canAdmin.value || !company || deleting.value) return;
  const context = identity.value;
  deleting.value = true;
  try {
    await API.deleteCompany(company.id, company.revision, {
      accountId: accountId.value,
    });
    if (context !== identity.value) return;
    deleteDialog.value?.close();
    deletingCompany.value = null;
    if (rows.value.length === 1 && page.value > 1)
      await changePage(page.value - 1);
    else await load();
  } catch (failure) {
    if (context !== identity.value) return;
    const code = failure.response?.data?.code;
    deleteError.value =
      code === 'COMPANY_IN_USE'
        ? t('CRM.DIRECTORY.COMPANY_IN_USE')
        : t('CRM.DIRECTORY.COMPANY_DELETE_FAILED');
  } finally {
    if (context === identity.value) deleting.value = false;
  }
};
const companyEdited = () => {
  editingCompany.value = null;
  load();
};
const companyTab = ref('overview');
const createCompany = () => {
  companyTab.value = 'overview';
  creating.value = true;
};
const cards = computed(() => [
  {
    label: t('CRM.DIRECTORY.TOTAL_COMPANIES'),
    value: meta.value.directory?.total,
    icon: 'i-lucide-building-2',
  },
  {
    label: t('CRM.DIRECTORY.ACTIVE_CLIENTS'),
    value: meta.value.directory?.customers,
    icon: 'i-lucide-users',
  },
  {
    label: t('CRM.DIRECTORY.PROSPECTS'),
    value: meta.value.directory?.prospects,
    icon: 'i-lucide-target',
  },
  {
    label: t('CRM.DIRECTORY.NO_OWNER'),
    value: meta.value.directory?.unassigned,
    icon: 'i-lucide-user-round-minus',
  },
]);
const companiesImport = computed(() => ({
  ...accountScopedRoute('jrc_customer_imports'),
  query: { kind: 'companies' },
}));
const canImport = computed(() =>
  checkPermissions(['administrator', 'contact_manage'])
);
const ascending = computed(() => filters.sort !== '-name');
const sortByName = () => {
  filters.sort = ascending.value ? '-name' : 'name';
  search();
};
const openCompany = (id, pane = 'overview') => {
  companyTab.value = pane;
  selection.value = id;
};
const initials = name =>
  name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map(part => part[0])
    .join('')
    .toUpperCase();
const badges = {
  customer: 'bg-n-teal-3 text-n-teal-11',
  prospect: 'bg-n-blue-3 text-n-blue-11',
  lead: 'bg-n-violet-3 text-n-violet-11',
};
const companyColors = [
  'bg-n-blue-3 text-n-blue-11',
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-violet-3 text-n-violet-11',
  'bg-n-amber-3 text-n-amber-11',
];
</script>

<template>
  <main
    class="h-full w-full overflow-auto bg-gradient-to-b from-n-blue-2 to-n-surface-1 p-3 text-n-slate-12 focus-visible:outline-n-brand sm:p-5"
    tabindex="0"
  >
    <div class="mx-auto flex max-w-[1600px] flex-col gap-4">
      <header class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex min-w-0 items-center gap-3">
          <span
            class="grid size-11 shrink-0 place-items-center rounded-xl bg-n-blue-3 text-n-blue-11"
            aria-hidden="true"
            ><span class="i-lucide-building-2 size-6"
          /></span>
          <div>
            <h1 class="text-2xl font-bold tracking-tight sm:text-3xl">
              {{ T.companies }}
            </h1>
            <p class="text-sm text-n-slate-11">
              {{ t('CRM.DIRECTORY.COMPANIES_HELP') }}
            </p>
          </div>
        </div>
        <div class="flex flex-wrap gap-2">
          <RouterLink
            v-if="canImport"
            :to="companiesImport"
            :class="buttonClass"
            class="inline-flex items-center gap-2 bg-n-solid-2"
          >
            <span
              class="i-lucide-upload size-4"
              aria-hidden="true"
            />{{ t('CRM.DIRECTORY.IMPORT') }}
          </RouterLink>
          <button
            type="button"
            :class="primaryClass"
            class="inline-flex items-center gap-2"
            @click="createCompany"
          >
            <span
              class="i-lucide-plus size-4"
              aria-hidden="true"
            />{{ T.newCompany }}
          </button>
        </div>
      </header>

      <DirectoryMetrics :cards="cards" />

      <form
        class="flex flex-wrap items-end gap-3 rounded-2xl border border-n-weak bg-n-solid-2 p-3 shadow-sm sm:p-4 [&_input]:!mb-0 [&_select]:!mb-0 [&_select]:!appearance-auto [&_select]:!bg-none"
        @submit.prevent="search"
      >
        <label class="relative min-w-[min(100%,16rem)] flex-1 text-sm">
          <span class="sr-only">{{ T.search }}</span>
          <span
            class="i-lucide-search pointer-events-none absolute start-3 top-1/2 mt-0.5 size-4 -translate-y-1/2 text-n-slate-10"
            aria-hidden="true"
          />
          <input
            v-model.trim="filters.q"
            type="search"
            :placeholder="t('CRM.DIRECTORY.SEARCH_COMPANIES')"
            :class="inputClass"
            class="!ps-9"
          />
        </label>
        <label class="min-w-28 flex-1 text-xs font-medium xl:max-w-40">
          {{ T.owner }}
          <select
            v-model="filters.owner_id"
            :class="inputClass"
          >
            <option value="">{{ T.all }}</option>
            <option value="unassigned">
              {{ t('CRM.DIRECTORY.NO_OWNER') }}
            </option>
            <option
              v-for="owner in metadata.owners"
              :key="owner.id"
              :value="owner.id"
            >
              {{ owner.name }}
            </option>
          </select>
        </label>
        <label class="min-w-28 flex-1 text-xs font-medium xl:max-w-40">
          {{ T.relationship }}
          <select
            v-model="filters.relationship_type"
            :class="inputClass"
          >
            <option value="">{{ T.all }}</option>
            <option
              v-for="(label, key) in RELATIONSHIPS"
              :key="key"
              :value="key"
            >
              {{ label }}
            </option>
          </select>
        </label>
        <label class="min-w-28 flex-1 text-xs font-medium xl:max-w-40">
          {{ T.city }}
          <input
            v-model.trim="filters.city"
            :class="inputClass"
            :placeholder="T.all"
          />
        </label>
        <button
          type="button"
          :class="buttonClass"
          class="inline-flex items-center gap-2 text-n-blue-11"
          :aria-expanded="moreFilters"
          @click="moreFilters = !moreFilters"
        >
          <span
            class="i-lucide-list-filter size-4"
            aria-hidden="true"
          />{{ t('CRM.DIRECTORY.MORE_FILTERS') }}
        </button>
        <button
          type="submit"
          :class="primaryClass"
          class="inline-flex items-center gap-2"
          :disabled="busy"
        >
          <span
            class="i-lucide-search size-4"
            aria-hidden="true"
          />{{ T.search }}
        </button>
        <div
          v-if="moreFilters"
          class="grid w-full gap-3 border-t border-n-weak pt-3 sm:grid-cols-3"
        >
          <label
            v-for="field in ['segment', 'economic_group']"
            :key="field"
            class="text-xs font-medium"
          >
            {{
              field === 'segment'
                ? t('CRM.CORPORATE_SEGMENTS.COMPANY_CLASSIFICATION')
                : FIELD_LABELS[field]
            }}
            <input
              v-model.trim="filters[field]"
              :class="inputClass"
            />
          </label>
          <label class="text-xs font-medium">
            {{ t('CRM.DIRECTORY.STATUS') }}
            <select
              v-model="filters.active"
              :class="inputClass"
            >
              <option value="">{{ T.all }}</option>
              <option value="true">{{ T.active }}</option>
              <option value="false">{{ T.inactive }}</option>
            </select>
          </label>
        </div>
      </form>

      <section
        class="min-w-0 rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
        :aria-busy="busy"
      >
        <p
          v-if="error"
          class="p-6 text-sm text-n-ruby-11"
          role="alert"
        >
          {{ error }}
        </p>
        <p
          v-else-if="busy"
          class="p-6 text-sm text-n-slate-11"
          role="status"
        >
          {{ T.loading }}
        </p>
        <p
          v-else-if="!rows.length"
          class="p-6 text-sm text-n-slate-11"
        >
          {{ T.noResults }}
        </p>
        <template v-else>
          <div class="relative overflow-x-auto rounded-t-2xl">
            <table class="w-full min-w-[820px] text-left text-sm">
              <thead
                class="border-b border-n-weak bg-n-blue-2 text-xs text-n-slate-11"
              >
                <tr>
                  <th
                    scope="col"
                    class="px-4 py-3"
                    :aria-sort="ascending ? 'ascending' : 'descending'"
                  >
                    <button
                      type="button"
                      class="inline-flex items-center gap-1.5 text-n-slate-12 hover:text-n-brand"
                      @click="sortByName"
                    >
                      {{ t('CRM.DIRECTORY.COMPANY') }}
                      <span
                        :class="
                          ascending
                            ? 'i-lucide-arrow-up'
                            : 'i-lucide-arrow-down'
                        "
                        class="size-3"
                        aria-hidden="true"
                      />
                    </button>
                  </th>
                  <th
                    scope="col"
                    class="px-3 py-3"
                  >
                    {{ FIELD_LABELS.tax_id }}
                  </th>
                  <th
                    scope="col"
                    class="px-3 py-3"
                  >
                    {{ T.contacts }}
                  </th>
                  <th
                    scope="col"
                    class="px-3 py-3"
                  >
                    {{ FIELD_LABELS.segment }}
                  </th>
                  <th
                    scope="col"
                    class="px-3 py-3"
                  >
                    {{ T.owner }}
                  </th>
                  <th
                    scope="col"
                    class="px-3 py-3"
                  >
                    {{ T.relationship }}
                  </th>
                  <th
                    scope="col"
                    class="px-3 py-3"
                  >
                    {{ T.city }}
                  </th>
                  <th
                    scope="col"
                    class="px-3 py-3"
                  >
                    <span class="sr-only">{{
                      t('CRM.DIRECTORY.ROW_ACTIONS')
                    }}</span>
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="company in rows"
                  :key="company.id"
                  class="hover:bg-n-blue-2/60"
                >
                  <td class="px-4 py-2">
                    <div class="flex items-center gap-2.5">
                      <span
                        :class="
                          companyColors[company.id % companyColors.length]
                        "
                        class="grid size-8 shrink-0 place-items-center rounded-lg"
                        aria-hidden="true"
                        ><span class="i-lucide-building-2 size-4"
                      /></span>
                      <div class="min-w-0">
                        <button
                          type="button"
                          class="text-left font-semibold text-n-slate-12 hover:text-n-brand"
                          @click="openCompany(company.id)"
                        >
                          {{ company.name }}
                        </button>
                        <p
                          v-if="company.trade_name"
                          class="m-0 text-xs text-n-slate-11"
                        >
                          {{ company.trade_name }}
                        </p>
                      </div>
                    </div>
                  </td>
                  <td class="whitespace-nowrap px-3 py-2 tabular-nums">
                    {{ company.tax_id || '—' }}
                  </td>
                  <td class="px-3 py-2">
                    <button
                      type="button"
                      class="inline-flex items-center gap-1.5 rounded-md px-1.5 py-1 font-semibold text-n-blue-11 hover:bg-n-blue-3"
                      :aria-label="
                        t('CRM.DIRECTORY.VIEW_COMPANY_CONTACTS', {
                          company: company.name,
                        })
                      "
                      @click="openCompany(company.id, 'contacts')"
                    >
                      <span
                        class="i-lucide-users size-4"
                        aria-hidden="true"
                      />{{ company.contact_count }}
                    </button>
                  </td>
                  <td class="px-3 py-2">{{ company.segment || '—' }}</td>
                  <td class="px-3 py-2">
                    <span
                      v-if="company.owner_name"
                      class="inline-flex items-center gap-2"
                    >
                      <span
                        class="grid size-7 shrink-0 place-items-center rounded-full bg-n-violet-3 text-[10px] font-semibold text-n-violet-11"
                        aria-hidden="true"
                        >{{ initials(company.owner_name) }}</span
                      >
                      {{ company.owner_name }}
                    </span>
                    <span v-else>—</span>
                  </td>
                  <td class="px-3 py-2">
                    <span
                      :class="
                        badges[company.relationship_type] ||
                        'bg-n-slate-3 text-n-slate-11'
                      "
                      class="whitespace-nowrap rounded-full px-2 py-1 text-xs font-semibold"
                      >{{
                        RELATIONSHIPS[company.relationship_type] || '—'
                      }}</span
                    >
                    <p
                      v-if="!company.active"
                      class="mt-1 text-xs text-n-slate-11"
                    >
                      {{ T.inactive }}
                    </p>
                  </td>
                  <td class="px-3 py-2">
                    {{
                      [company.city, company.state]
                        .filter(Boolean)
                        .join(' - ') || '—'
                    }}
                  </td>
                  <td class="px-3 py-2 text-right">
                    <div class="flex justify-end gap-1">
                      <button
                        type="button"
                        class="grid size-8 place-items-center rounded-lg bg-n-blue-3 text-n-blue-11 hover:bg-n-blue-4"
                        :title="T.editCompany"
                        :aria-label="T.editCompany"
                        @click="editingCompany = company"
                      >
                        <span
                          class="i-lucide-pencil size-4"
                          aria-hidden="true"
                        />
                      </button>
                      <button
                        v-if="canAdmin"
                        type="button"
                        class="grid size-8 place-items-center rounded-lg bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4 disabled:opacity-50"
                        :title="t('CRM.DIRECTORY.DELETE_COMPANY')"
                        :aria-label="t('CRM.DIRECTORY.DELETE_COMPANY')"
                        :disabled="deleting"
                        @click="confirmCompanyDelete(company)"
                      >
                        <span
                          class="i-lucide-trash-2 size-4"
                          aria-hidden="true"
                        />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <PaginationFooter
            :current-page="page"
            :items-per-page="meta.per_page || 25"
            :total-items="meta.total"
            current-page-info="CRM.DIRECTORY.SHOWING_COMPANIES"
            numbered
            @update:current-page="changePage"
          />
        </template>
      </section>
    </div>

    <CompanyEditorDialog
      v-if="creating"
      :key="identity"
      @saved="saved"
      @close="closeEditor"
    />
    <CompanyEditorDialog
      v-if="editingCompany"
      :key="`${identity}:${editingCompany.id}`"
      :company="editingCompany"
      @saved="companyEdited"
      @close="editingCompany = null"
    />
    <Dialog
      v-if="deletingCompany"
      ref="deleteDialog"
      type="alert"
      :title="t('CRM.DIRECTORY.DELETE_COMPANY')"
      :description="
        t('CRM.DIRECTORY.COMPANY_DELETE_CONFIRM', {
          name: deletingCompany.name,
        })
      "
      :confirm-button-label="t('CRM.DIRECTORY.DELETE_COMPANY')"
      :is-loading="deleting"
      :disable-confirm-button="deleting"
      @confirm="deleteCompany"
      @close="deletingCompany = null"
    >
      <p
        v-if="deleteError"
        role="alert"
        class="mt-3 text-sm text-n-ruby-11"
      >
        {{ deleteError }}
      </p>
    </Dialog>
    <CompanyDetailsDialog
      v-if="selection"
      :key="`${identity}:${selection}:${companyTab}`"
      :company-id="selection"
      :initial-tab="companyTab"
      @close="selection = null"
      @updated="load"
    />
  </main>
</template>
