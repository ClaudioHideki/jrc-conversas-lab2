<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConfigurationAuditDetails from './ConfigurationAuditDetails.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
});
const route = useRoute();
const { t } = useI18n();
const items = ref([]);
const window = ref(null);
const loading = ref(false);
const error = ref('');
const selected = ref(null);
const detailLoading = ref(false);
const detailError = ref('');
const detailTimezone = ref('UTC');
const dialog = ref(null);
let alive = true;
let listGeneration = 0;
let detailGeneration = 0;
const labels = computed(() => ({
  title: t('JRC_CONTACT_CENTER.RECENT_ACTIVITY.TITLE'),
  all: t('JRC_CONTACT_CENTER.RECENT_ACTIVITY.ALL'),
  period: t('JRC_CONTACT_CENTER.RECENT_ACTIVITY.PERIOD'),
  empty: t('JRC_CONTACT_CENTER.RECENT_ACTIVITY.EMPTY'),
}));
const resourceLabels = computed(() => ({
  unit: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.UNIT'),
  queue: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.QUEUE'),
  membership: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.MEMBERSHIP'),
  role: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ROLE'),
  access: t('JRC_CONTACT_CENTER.ACCESS.TITLE'),
  ivr_revision: t('JRC_CONTACT_CENTER.LOCAL_IVR.AUDIT_REVISION'),
}));
const operationLabels = computed(() => ({
  create: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CREATE'),
  update: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.UPDATE'),
  destroy: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.DESTROY'),
}));
const resourceLabel = row =>
  resourceLabels.value[row.resource_type] ||
  t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.RESOURCE');
const operationLabel = row =>
  operationLabels.value[row.operation] ||
  t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.OPERATION');
const date = (value, timezone) =>
  new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: timezone,
  }).format(new Date(value));
const actor = row =>
  row.actor_name ||
  (row.actor_id
    ? `${t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.ACTOR')} #${row.actor_id}`
    : t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.SYSTEM'));
const destination = (row = null) => {
  const query = Object.fromEntries(
    Object.entries(route.query).filter(
      ([key]) => !key.startsWith('audit_config_') && key !== 'audit_source'
    )
  );
  query.audit_source = 'configuration';
  if (row) {
    query.audit_config_resource_type = row.resource_type;
    query.audit_config_resource_id = String(row.resource_id);
    query.audit_config_history = 'true';
  }
  return {
    name: 'jrc_contact_center_admin_section',
    params: { accountId: props.accountId, section: 'audit' },
    query,
  };
};
const errorLabel = reason =>
  [401, 403, 404].includes(reason?.response?.status)
    ? t('JRC_CONTACT_CENTER.ADMIN.DENIED')
    : t('JRC_CONTACT_CENTER.COMMON.ERROR');
const stopDetails = () => {
  detailGeneration += 1;
  selected.value = null;
  detailLoading.value = false;
  detailError.value = '';
};
const load = async () => {
  listGeneration += 1;
  const version = listGeneration;
  const account = String(props.accountId);
  items.value = [];
  window.value = null;
  error.value = '';
  loading.value = true;
  stopDetails();
  dialog.value?.close();
  try {
    const response = await API.configurationAudits(account, {
      page: '1',
      per_page: 5,
    });
    if (
      !alive ||
      version !== listGeneration ||
      account !== String(props.accountId)
    )
      return;
    items.value = response.data.items;
    window.value = response.data.window;
  } catch (reason) {
    if (
      alive &&
      version === listGeneration &&
      account === String(props.accountId)
    )
      error.value = errorLabel(reason);
  } finally {
    if (
      alive &&
      version === listGeneration &&
      account === String(props.accountId)
    )
      loading.value = false;
  }
};
const showDetail = async row => {
  detailGeneration += 1;
  const version = detailGeneration;
  const account = String(props.accountId);
  selected.value = null;
  detailError.value = '';
  detailLoading.value = true;
  await nextTick();
  if (!alive || version !== detailGeneration) return;
  dialog.value?.open();
  try {
    const response = await API.configurationAudit(account, row.id);
    if (
      !alive ||
      version !== detailGeneration ||
      account !== String(props.accountId)
    )
      return;
    selected.value = response.data.item;
    detailTimezone.value = response.data.timezone;
  } catch (reason) {
    if (
      alive &&
      version === detailGeneration &&
      account === String(props.accountId)
    ) {
      detailError.value = errorLabel(reason);
      if ([401, 403, 404].includes(reason?.response?.status)) {
        items.value = [];
        error.value = detailError.value;
      }
    }
  } finally {
    if (
      alive &&
      version === detailGeneration &&
      account === String(props.accountId)
    )
      detailLoading.value = false;
  }
};
watch(() => props.accountId, load, { immediate: true });
onBeforeUnmount(() => {
  alive = false;
  listGeneration += 1;
  stopDetails();
  items.value = [];
  window.value = null;
});
</script>

<template>
  <section
    class="min-w-0 space-y-4 rounded-xl border border-n-blue-6 bg-n-solid-2 p-4"
    data-recent-configuration
  >
    <header class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <h2 class="font-semibold text-n-slate-12">{{ labels.title }}</h2>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.LOCAL_ONLY') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-3 text-sm">
        <Button
          :label="t('JRC_CONTACT_CENTER.COMMON.REFRESH')"
          faded
          slate
          :disabled="loading"
          data-recent-refresh
          @click="load"
        />
        <RouterLink
          :to="destination()"
          class="self-center text-n-blue-11"
          data-recent-all
        >
          {{ labels.all }}
        </RouterLink>
      </div>
    </header>
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <p v-else-if="error" role="alert" class="text-sm text-n-ruby-11">
      {{ error }}
    </p>
    <template v-else-if="window">
      <p class="break-words text-xs text-n-slate-11" data-recent-window>
        {{
          t('JRC_CONTACT_CENTER.RECENT_ACTIVITY.WINDOW', {
            period: labels.period,
            from: window.from.split('-').reverse().join('/'),
            to: window.to.split('-').reverse().join('/'),
            timezone: window.timezone,
          })
        }}
      </p>
      <p v-if="!items.length" class="text-sm text-n-slate-11">
        {{ labels.empty }}
      </p>
      <ul v-else class="space-y-2">
        <li v-for="row in items" :key="row.id">
          <button
            type="button"
            class="w-full min-w-0 rounded-lg border border-n-blue-6 p-3 text-left hover:bg-n-blue-2 focus-visible:ring-2 focus-visible:ring-n-blue-7"
            :data-recent-event="row.id"
            @click="showDetail(row)"
          >
            <span class="block break-words text-sm font-medium text-n-slate-12">
              {{
                t('JRC_CONTACT_CENTER.RECENT_ACTIVITY.EVENT', {
                  operation: operationLabel(row),
                  resource: resourceLabel(row),
                  id: row.resource_id,
                })
              }}
            </span>
            <span
              v-if="row.after?.name || row.before?.name"
              class="mt-1 block break-words text-sm text-n-slate-12"
            >
              {{ row.after?.name || row.before?.name }}
            </span>
            <span class="mt-1 block break-words text-xs text-n-slate-11">
              {{
                t('JRC_CONTACT_CENTER.RECENT_ACTIVITY.WHEN', {
                  date: date(row.created_at, window.timezone),
                  actor: actor(row),
                })
              }}
            </span>
          </button>
        </li>
      </ul>
    </template>
    <Dialog
      ref="dialog"
      contained
      overflow-y-auto
      width="3xl"
      :title="t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.DETAILS')"
      :use-form="false"
      :show-cancel-button="false"
      @close="stopDetails"
    >
      <p v-if="detailLoading" role="status">
        {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
      </p>
      <p v-else-if="detailError" role="alert" class="text-n-ruby-11">
        {{ detailError }}
      </p>
      <ConfigurationAuditDetails
        v-else-if="selected"
        :record="selected"
        :date="date(selected.created_at, detailTimezone)"
        :resource-label="resourceLabel(selected)"
        :operation-label="operationLabel(selected)"
      />
      <template #footer>
        <RouterLink
          v-if="selected"
          :to="destination(selected)"
          class="text-sm text-n-blue-11"
          data-recent-history
        >
          {{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.HISTORY') }}
        </RouterLink>
        <Button
          :label="t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CLOSE')"
          faded
          slate
          data-recent-close
          @click="dialog.close()"
        />
      </template>
    </Dialog>
  </section>
</template>
