<script setup>
import { computed, nextTick, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConfigurationAuditDetails from './ConfigurationAuditDetails.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const text = {
  title: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.TITLE'),
  local: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.LOCAL_ONLY'),
  from: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.FROM'),
  to: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.TO'),
  resource: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.RESOURCE'),
  resourceId: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.RESOURCE_ID'),
  operation: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.OPERATION'),
  actor: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACTOR'),
  correlation: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CORRELATION'),
  unit: t('JRC_CONTACT_CENTER.ADMIN.UNIT'),
  all: t('JRC_CONTACT_CENTER.ADMIN.ALL'),
  filter: t('JRC_CONTACT_CENTER.ADMIN.FILTER'),
  clear: t('JRC_CONTACT_CENTER.ADMIN.CLEAR'),
  export: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.EXPORT'),
  details: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.DETAILS'),
  history: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.HISTORY'),
  allHistory: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ALL_HISTORY'),
  select: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SELECT_EVENT'),
  close: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CLOSE'),
  loading: t('JRC_CONTACT_CENTER.COMMON.LOADING'),
  empty: t('JRC_CONTACT_CENTER.COMMON.EMPTY'),
  total: t('JRC_CONTACT_CENTER.ADMIN.TOTAL'),
  page: t('JRC_CONTACT_CENTER.ADMIN.PAGE'),
  previous: t('JRC_CONTACT_CENTER.ADMIN.PREVIOUS'),
  next: t('JRC_CONTACT_CENTER.ADMIN.NEXT'),
  pagination: t('JRC_CONTACT_CENTER.ADMIN.PAGINATION'),
  system: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SYSTEM'),
  error: t('JRC_CONTACT_CENTER.COMMON.ERROR'),
  denied: t('JRC_CONTACT_CENTER.ADMIN.DENIED'),
  datesError: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.DATES_ERROR'),
  filterError: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.FILTER_ERROR'),
  exportLimit: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.EXPORT_LIMIT'),
  exportIntegrity: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.EXPORT_INTEGRITY'),
  notEnabled: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NOT_ENABLED'),
};
const resourceLabels = {
  unit: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.UNIT'),
  queue: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.QUEUE'),
  membership: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.MEMBERSHIP'),
  role: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ROLE'),
  access: t('JRC_CONTACT_CENTER.ACCESS.TITLE'),
  ivr_revision: t('JRC_CONTACT_CENTER.LOCAL_IVR.AUDIT_REVISION'),
  acw_policy: t('JRC_CONTACT_CENTER.ACW_OPERATION.POLICY_TITLE'),
};
const operationLabels = {
  create: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CREATE'),
  update: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.UPDATE'),
  destroy: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.DESTROY'),
};
const filterKeys = [
  'from',
  'to',
  'resource_type',
  'resource_id',
  'operation',
  'actor_id',
  'unit_id',
  'correlation_id',
  'history',
];
const prefix = 'audit_config_';
const signature = query =>
  JSON.stringify(['page', ...filterKeys].map(key => query[prefix + key] || ''));
const filters = reactive(Object.fromEntries(filterKeys.map(key => [key, ''])));
const items = ref([]);
const actors = ref([]);
const meta = ref({ total: 0, pages: 0, page: 1 });
const timezone = ref('UTC');
const loading = ref(false);
const listError = ref('');
const selected = ref(null);
const detailError = ref('');
const loadingDetail = ref(false);
const dialog = ref(null);
const exporting = ref(false);
const exportError = ref('');
let alive = true;
let listGeneration = 0;
let detailGeneration = 0;
let downloadUrl = null;
const canExport = computed(() => props.context.capabilities.reports === true);
const currentAccount = value => alive && String(props.accountId) === value;
const requestFilters = () =>
  Object.fromEntries(
    filterKeys.map(key => [key, String(route.query[prefix + key] || '')])
  );
const formattedDate = value =>
  new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: timezone.value,
  }).format(new Date(value));

const errorLabel = async error => {
  let body = error?.response?.data;
  if (body instanceof Blob) {
    try {
      body = JSON.parse(await body.text());
    } catch {
      body = null;
    }
  }
  if ([401, 403, 404].includes(error?.response?.status)) return text.denied;
  const labels = {
    invalid_audit_dates: text.datesError,
    invalid_audit_filter: text.filterError,
    audit_export_limit_exceeded: text.exportLimit,
    audit_integrity_failed: text.exportIntegrity,
    native_audit_unavailable: text.notEnabled,
  };
  return labels[body?.error || error?.message] || text.error;
};
const restoreFilters = () => {
  filterKeys.forEach(key => {
    filters[key] = String(route.query[prefix + key] || '');
  });
};
const stopDetails = () => {
  detailGeneration += 1;
  loadingDetail.value = false;
};
const load = async () => {
  listGeneration += 1;
  const version = listGeneration;
  const account = String(props.accountId);
  loading.value = true;
  listError.value = '';
  exportError.value = '';
  items.value = [];
  actors.value = [];
  meta.value = { total: 0, pages: 0, page: 1 };
  timezone.value = 'UTC';
  selected.value = null;
  detailError.value = '';
  stopDetails();
  dialog.value?.close();
  try {
    const response = await API.configurationAudits(account, {
      ...requestFilters(),
      page: String(route.query[prefix + 'page'] || '1'),
      per_page: 20,
    });
    if (!currentAccount(account) || version !== listGeneration) return;
    items.value = response.data.items;
    actors.value = response.data.actors;
    meta.value = response.data.meta;
    timezone.value = response.data.window.timezone;
    if (!route.query[prefix + 'from'])
      filters.from = response.data.window.from || '';
    if (!route.query[prefix + 'to']) filters.to = response.data.window.to || '';
  } catch (error) {
    const message = await errorLabel(error);
    if (currentAccount(account) && version === listGeneration)
      listError.value = message;
  } finally {
    if (currentAccount(account) && version === listGeneration)
      loading.value = false;
  }
};
const replaceQuery = async query => {
  const unchanged = signature(query) === signature(route.query);
  await router.replace({ query });
  if (unchanged) {
    restoreFilters();
    await load();
  }
};
const apply = (history = false) => {
  const query = { ...route.query };
  filterKeys.forEach(key => {
    let value = String(filters[key] ?? '').trim();
    if (key === 'history') value = history ? 'true' : '';
    if (value) query[prefix + key] = value;
    else delete query[prefix + key];
  });
  query[prefix + 'page'] = '1';
  return replaceQuery(query);
};
const clear = () => {
  const query = { ...route.query };
  ['page', ...filterKeys].forEach(key => {
    delete query[prefix + key];
  });
  return replaceQuery(query);
};
const changePage = page =>
  replaceQuery({ ...route.query, [prefix + 'page']: String(page) });
const loadDetail = async (row, popup = false) => {
  detailGeneration += 1;
  const version = detailGeneration;
  const account = String(props.accountId);
  selected.value = null;
  detailError.value = '';
  loadingDetail.value = true;
  if (popup) {
    await nextTick();
    dialog.value?.open();
  }
  try {
    const response = await API.configurationAudit(account, row.id);
    if (!currentAccount(account) || version !== detailGeneration) return;
    selected.value = response.data.item;
    timezone.value = response.data.timezone;
  } catch (error) {
    const message = await errorLabel(error);
    if (currentAccount(account) && version === detailGeneration)
      detailError.value = message;
  } finally {
    if (currentAccount(account) && version === detailGeneration)
      loadingDetail.value = false;
  }
};
const showHistory = () => {
  filters.resource_type = selected.value.resource_type;
  filters.resource_id = String(selected.value.resource_id);
  filters.actor_id = '';
  filters.unit_id = '';
  filters.operation = '';
  filters.correlation_id = '';
  filters.from = '';
  filters.to = '';
  return apply(true);
};
const download = async () => {
  const account = String(props.accountId);
  const query = signature(route.query);
  const generation = listGeneration;
  exporting.value = true;
  exportError.value = '';
  try {
    const response = await API.exportConfigurationAudits(
      account,
      requestFilters()
    );
    const digest = await crypto.subtle.digest(
      'SHA-256',
      await response.data.arrayBuffer()
    );
    const hash = Array.from(new Uint8Array(digest), value =>
      value.toString(16).padStart(2, '0')
    ).join('');
    if (hash !== response.headers['x-content-sha256'])
      throw new Error('audit_integrity_failed');
    if (
      !currentAccount(account) ||
      generation !== listGeneration ||
      query !== signature(route.query) ||
      !canExport.value
    )
      return;
    const url = URL.createObjectURL(response.data);
    downloadUrl = url;
    const link = document.createElement('a');
    link.href = url;
    link.download = 'call-center-auditoria.csv';
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => {
      URL.revokeObjectURL(url);
      if (downloadUrl === url) downloadUrl = null;
    }, 1000);
  } catch (error) {
    const message = await errorLabel(error);
    if (currentAccount(account) && query === signature(route.query))
      exportError.value = message;
  } finally {
    if (currentAccount(account)) exporting.value = false;
  }
};
watch(
  () => [props.accountId, signature(route.query)],
  () => {
    restoreFilters();
    load();
  },
  { immediate: true, flush: 'sync' }
);
onBeforeUnmount(() => {
  alive = false;
  listGeneration += 1;
  detailGeneration += 1;
  if (downloadUrl) URL.revokeObjectURL(downloadUrl);
});
</script>

<template>
  <section class="min-w-0 space-y-4 text-n-slate-12" data-configuration-audit>
    <header
      class="flex flex-wrap items-start justify-between gap-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-4"
    >
      <div class="min-w-0">
        <h2 class="text-lg font-semibold">{{ text.title }}</h2>
        <p class="mt-2 text-sm text-n-blue-11">{{ text.local }}</p>
      </div>
      <Button
        v-if="canExport"
        data-audit-export
        :label="text.export"
        icon="i-lucide-download"
        :disabled="loading || exporting"
        :is-loading="exporting"
        @click="download"
      />
    </header>
    <form
      class="grid min-w-0 gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 sm:grid-cols-2 xl:grid-cols-4"
      @submit.prevent="apply(false)"
    >
      <label class="text-sm">
        <span>{{ text.from }}</span>
        <input
          v-model="filters.from"
          type="date"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <label class="text-sm">
        <span>{{ text.to }}</span>
        <input
          v-model="filters.to"
          type="date"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <label class="text-sm">
        <span>{{ text.resource }}</span>
        <select
          v-model="filters.resource_type"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ text.all }}</option>
          <option
            v-for="(label, key) in resourceLabels"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select></label
      >
      <label class="text-sm">
        <span>{{ text.resourceId }}</span>
        <input
          v-model="filters.resource_id"
          type="number"
          min="1"
          step="1"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <label class="text-sm">
        <span>{{ text.operation }}</span>
        <select
          v-model="filters.operation"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ text.all }}</option>
          <option
            v-for="(label, key) in operationLabels"
            :key="key"
            :value="key"
          >
            {{ label }}
          </option>
        </select></label
      >
      <label class="text-sm">
        <span>{{ text.unit }}</span>
        <select
          v-model="filters.unit_id"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ text.all }}</option>
          <option
            v-for="unit in context.units"
            :key="unit.id"
            :value="String(unit.id)"
          >
            {{ unit.name }}
          </option>
        </select></label
      >
      <label class="text-sm">
        <span>{{ text.actor }}</span>
        <select
          v-model="filters.actor_id"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
        >
          <option value="">{{ text.all }}</option>
          <option
            v-for="actor in actors"
            :key="actor.id"
            :value="String(actor.id)"
          >
            {{ actor.name || '#' + actor.id }}
          </option>
        </select></label
      >
      <label class="text-sm">
        <span>{{ text.correlation }}</span>
        <input
          v-model.trim="filters.correlation_id"
          type="text"
          maxlength="100"
          :disabled="loading || exporting"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
      /></label>
      <div class="flex flex-wrap gap-2 sm:col-span-2 xl:col-span-4">
        <Button
          type="submit"
          :label="text.filter"
          :disabled="loading || exporting"
        />
        <Button
          type="button"
          faded
          slate
          :label="text.clear"
          :disabled="loading || exporting"
          @click="clear"
        />
      </div>
    </form>
    <p
      v-if="filters.history === 'true'"
      role="status"
      class="rounded-lg bg-n-blue-2 p-3 text-sm text-n-blue-11"
    >
      {{ text.allHistory }}
    </p>
    <p
      v-if="exportError"
      role="alert"
      class="text-sm text-n-ruby-11"
      data-audit-export-error
    >
      {{ exportError }}
    </p>
    <p v-if="loading" role="status">{{ text.loading }}</p>
    <p
      v-else-if="listError"
      role="alert"
      class="rounded-lg border border-n-ruby-6 p-4 text-n-ruby-11"
      data-audit-list-error
    >
      {{ listError }}
    </p>
    <template v-else>
      <div class="grid min-w-0 gap-4 xl:grid-cols-3">
        <div class="min-w-0 space-y-3 xl:col-span-2">
          <p class="text-sm text-n-slate-11">
            {{ text.total }} {{ meta.total }}
          </p>
          <p v-if="!items.length" role="status">{{ text.empty }}</p>
          <article
            v-for="row in items"
            :key="row.id"
            class="flex min-w-0 flex-wrap items-center justify-between gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
            data-audit-row
          >
            <button
              type="button"
              class="min-w-0 flex-1 text-start"
              @click="loadDetail(row)"
            >
              <strong class="block break-words"
                >{{ resourceLabels[row.resource_type] }} #{{
                  row.resource_id
                }}
                · {{ operationLabels[row.operation] }}</strong
              >
              <time class="mt-1 block text-sm text-n-slate-11">{{
                formattedDate(row.created_at)
              }}</time>
              <span class="mt-1 block break-words text-sm">{{
                row.actor_name ||
                (row.actor_id ? '#' + row.actor_id : text.system)
              }}</span>
            </button>
            <Button
              data-audit-detail
              faded
              blue
              :label="text.details"
              @click="loadDetail(row, true)"
            />
          </article>
          <nav
            v-if="meta.pages > 1"
            class="flex flex-wrap items-center gap-3 text-sm"
            :aria-label="text.pagination"
          >
            <Button
              :label="text.previous"
              faded
              slate
              :disabled="meta.page <= 1 || loading"
              @click="changePage(meta.page - 1)"
            />
            <span>{{ text.page }} {{ meta.page }} / {{ meta.pages }}</span>
            <Button
              :label="text.next"
              faded
              slate
              :disabled="meta.page >= meta.pages || loading"
              @click="changePage(meta.page + 1)"
            />
          </nav>
        </div>
        <aside
          class="min-w-0 space-y-3 self-start rounded-xl border border-n-blue-6 bg-n-solid-2 p-4"
          data-audit-preview
        >
          <h3 class="font-semibold">{{ text.details }}</h3>
          <p v-if="loadingDetail" role="status" class="text-n-slate-12">
            {{ text.loading }}
          </p>
          <p v-else-if="detailError" role="alert" class="text-n-ruby-11">
            {{ detailError }}
          </p>
          <template v-else-if="selected">
            <ConfigurationAuditDetails
              compact
              :record="selected"
              :date="formattedDate(selected.created_at)"
              :resource-label="resourceLabels[selected.resource_type]"
              :operation-label="operationLabels[selected.operation]"
            />
            <div class="flex flex-wrap gap-2">
              <Button :label="text.details" @click="dialog.open()" />
              <Button :label="text.history" faded slate @click="showHistory" />
            </div>
          </template>
          <p v-else class="text-sm text-n-slate-11">{{ text.select }}</p>
        </aside>
      </div>
    </template>
    <Dialog
      ref="dialog"
      contained
      overflow-y-auto
      width="3xl"
      :title="text.details"
      :use-form="false"
      :show-cancel-button="false"
      @close="stopDetails"
    >
      <p v-if="loadingDetail" role="status">{{ text.loading }}</p>
      <p v-else-if="detailError" role="alert" class="text-n-ruby-11">
        {{ detailError }}
      </p>
      <ConfigurationAuditDetails
        v-else-if="selected"
        :record="selected"
        :date="formattedDate(selected.created_at)"
        :resource-label="resourceLabels[selected.resource_type]"
        :operation-label="operationLabels[selected.operation]"
      />
      <template #footer>
        <Button
          type="button"
          faded
          slate
          :label="text.close"
          @click="dialog.close()"
        />
      </template>
    </Dialog>
  </section>
</template>
