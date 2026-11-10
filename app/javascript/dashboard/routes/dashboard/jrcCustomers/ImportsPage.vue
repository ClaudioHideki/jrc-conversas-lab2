<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ImportMapping from './components/ImportMapping.vue';
import ImportPreview from './components/ImportPreview.vue';
import ImportHistory from './components/ImportHistory.vue';
import ImportResult from './components/ImportResult.vue';
import CompanyDetailsDialog from './components/CompanyDetailsDialog.vue';
import ContactDetailsDialog from './components/ContactDetailsDialog.vue';
import { useCustomerImports } from './useCustomerImports';
import { inputClass, buttonClass, primaryClass } from './copy';
const { t, tm } = useI18n();
const copy = computed(() => tm('CRM.CUSTOMER_IMPORTS'));
const {
  metadata,
  run,
  source,
  file,
  kind,
  delimiter,
  mapping,
  options,
  preview,
  tab,
  busy,
  error,
  history,
  filters,
  records,
  resultView,
  canImport,
  date,
  identity,
  upload,
  inspect,
  apply,
  template,
  exportErrors,
  loadHistory,
  openRun,
  startNew,
  pageRecords,
  showResult,
} = useCustomerImports();
const confirmDialog = ref(null);
const selection = ref(null);
const mappingKey = ref(0);
const tabs = [
  { key: 'file', tone: 'border-n-blue-7 bg-n-blue-3 text-n-blue-12' },
  { key: 'mapping', tone: 'border-n-amber-7 bg-n-amber-3 text-n-amber-12' },
  { key: 'preview', tone: 'border-n-violet-7 bg-n-violet-3 text-n-violet-12' },
  { key: 'result', tone: 'border-n-teal-7 bg-n-teal-3 text-n-teal-12' },
  { key: 'history', tone: 'border-n-blue-7 bg-n-blue-3 text-n-blue-12' },
];
watch(identity, () => {
  selection.value = null;
  confirmDialog.value?.close();
});
watch(
  () => run.value?.id,
  () => {
    mappingKey.value += 1;
  }
);
const switchTab = key => {
  if (key === 'file') startNew();
  else if (key === 'history') loadHistory();
  else tab.value = key;
};
const disabledTab = key =>
  busy.value ||
  !canImport.value ||
  (key === 'mapping' && !source.value) ||
  (key === 'preview' && !preview.value) ||
  (key === 'result' && run.value?.status !== 'completed');
const updateOptions = values => {
  Object.assign(options, values);
};
const applyConfirmed = async () => {
  await apply();
  confirmDialog.value?.close();
};
</script>

<template>
  <main
    class="h-full min-w-0 w-full overflow-auto bg-n-solid-1 p-4 text-n-slate-12 sm:p-6"
    data-testid="customer-imports"
  >
    <header class="mb-5 rounded-xl border border-n-blue-6 bg-n-blue-3 p-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 class="text-xl font-bold text-n-blue-12">
            {{ t('CRM.CUSTOMER_IMPORTS.TITLE') }}
          </h1>
          <p class="mt-1 text-sm text-n-blue-11">
            {{ t('CRM.CUSTOMER_IMPORTS.HELP') }}
          </p>
        </div>
        <button
          type="button"
          :class="primaryClass"
          :disabled="busy || !canImport"
          @click="startNew"
        >
          {{ t('CRM.CUSTOMER_IMPORTS.NEW') }}
        </button>
      </div>
    </header>
    <nav
      class="mb-5 flex flex-wrap gap-2"
      :aria-label="t('CRM.CUSTOMER_IMPORTS.STEPS')"
    >
      <button
        v-for="item in tabs"
        :key="item.key"
        type="button"
        class="rounded-lg border px-4 py-2 text-sm font-semibold disabled:opacity-40"
        :class="[item.tone, tab === item.key ? 'ring-2 ring-n-brand' : '']"
        :aria-pressed="tab === item.key"
        :disabled="disabledTab(item.key)"
        @click="switchTab(item.key)"
      >
        {{ copy.TABS[item.key] }}
      </button>
    </nav>
    <p
      v-if="error"
      role="alert"
      class="mb-4 rounded-lg border border-n-ruby-7 bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
      class="mb-3 text-sm text-n-slate-11"
    >
      {{ t('CRM.CUSTOMER_IMPORTS.LOADING') }}
    </p>
    <p
      v-if="metadata && !canImport"
      class="rounded-xl border border-n-amber-7 bg-n-amber-3 p-4 text-n-amber-12"
    >
      {{ t('CRM.CUSTOMER_IMPORTS.NO_PERMISSION') }}
    </p>
    <section
      v-else-if="metadata"
      class="rounded-xl border border-n-weak bg-n-solid-2 p-4 sm:p-5"
      :aria-busy="busy"
    >
      <form
        v-if="tab === 'file'"
        class="space-y-5"
        @submit.prevent="upload"
      >
        <div class="grid gap-4 sm:grid-cols-2">
          <label class="text-sm font-semibold">
            {{ t('CRM.CUSTOMER_IMPORTS.KIND') }}
            <select
              v-model="kind"
              :class="inputClass"
              :disabled="busy"
            >
              <option
                v-for="key in metadata.available_kinds"
                :key="key"
                :value="key"
              >
                {{ copy.KINDS[key] }}
              </option>
            </select>
          </label>
          <label class="text-sm font-semibold">
            {{ t('CRM.CUSTOMER_IMPORTS.SEPARATOR') }}
            <select
              v-model="delimiter"
              :class="inputClass"
              :disabled="busy"
            >
              <option value="">{{ t('CRM.CUSTOMER_IMPORTS.AUTO') }}</option>
              <option value=",">{{ t('CRM.CUSTOMER_IMPORTS.COMMA') }}</option>
              <option value=";">
                {{ t('CRM.CUSTOMER_IMPORTS.SEMICOLON') }}
              </option>
              <option :value="String.fromCharCode(9)">
                {{ t('CRM.CUSTOMER_IMPORTS.TAB_SEPARATOR') }}
              </option>
            </select>
          </label>
        </div>
        <p class="text-sm text-n-slate-11">
          {{ t('CRM.CUSTOMER_IMPORTS.FILE_HELP', { rows: metadata.max_rows }) }}
        </p>
        <label
          class="block rounded-lg border border-dashed border-n-blue-7 bg-n-blue-2 p-5 text-sm font-semibold"
        >
          {{ t('CRM.CUSTOMER_IMPORTS.SELECT_FILE') }}
          <input
            :key="`${identity}:${run?.id || 'new'}`"
            type="file"
            accept=".csv,text/csv"
            :disabled="busy"
            class="mt-3 block w-full text-sm"
            @change="file = $event.target.files?.[0] || null"
        /></label>
        <div class="flex flex-wrap gap-3">
          <button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="template"
          >
            {{ t('CRM.CUSTOMER_IMPORTS.TEMPLATE') }}
          </button>
          <button
            type="submit"
            :class="primaryClass"
            :disabled="busy || !file"
          >
            {{ t('CRM.CUSTOMER_IMPORTS.UPLOAD') }}
          </button>
        </div>
      </form>
      <template v-else>
        <p
          v-if="run && tab !== 'history'"
          class="mb-4 break-words text-sm font-semibold"
        >
          {{
            t('CRM.CUSTOMER_IMPORTS.FILE_CONTEXT', {
              filename: run.filename,
              kind: copy.KINDS[run.kind],
            })
          }}
        </p>
        <ImportMapping
          v-if="tab === 'mapping' && source"
          :key="mappingKey"
          :source="source"
          :mapping="mapping"
          :options="options"
          :disabled="busy"
          @mapping="mapping = $event"
          @options="updateOptions"
          @preview="inspect"
        />
        <ImportPreview
          v-if="tab === 'preview' && preview"
          :preview="preview"
          :disabled="busy"
          @confirm="confirmDialog.open()"
          @errors="exportErrors"
          @back="tab = 'mapping'"
        />
        <ImportResult
          v-if="tab === 'result' && run"
          :run="run"
          :records="records"
          :view="resultView"
          :disabled="busy"
          @view="showResult"
          @page="pageRecords"
          @open="selection = $event"
          @errors="exportErrors"
        />
        <ImportHistory
          v-if="tab === 'history'"
          :history="history"
          :filters="filters"
          :kinds="metadata.available_kinds"
          :date="date"
          :disabled="busy"
          @filters="Object.assign(filters, $event)"
          @search="loadHistory()"
          @page="loadHistory"
          @open="openRun"
        />
      </template>
    </section>
    <Dialog
      ref="confirmDialog"
      :title="t('CRM.CUSTOMER_IMPORTS.APPLY')"
      :description="t('CRM.CUSTOMER_IMPORTS.CONFIRM_HELP')"
      :confirm-button-label="t('CRM.CUSTOMER_IMPORTS.CONFIRM')"
      :is-loading="busy"
      :dismissible="!busy"
      contained
      @confirm="applyConfirmed"
    />
    <CompanyDetailsDialog
      v-if="selection?.entity === 'company'"
      :company-id="selection.record_id"
      @close="selection = null"
      @updated="pageRecords(records.meta.page)"
    />
    <ContactDetailsDialog
      v-if="selection?.entity === 'contact'"
      :contact-id="selection.record_id"
      @close="selection = null"
      @updated="pageRecords(records.meta.page)"
    />
  </main>
</template>
