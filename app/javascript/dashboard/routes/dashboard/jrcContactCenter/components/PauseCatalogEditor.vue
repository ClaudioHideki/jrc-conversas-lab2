<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcContactCenter';
import ConfigurationRevisionConflict from './ConfigurationRevisionConflict.vue';
import AgentStateHistory from './AgentStateHistory.vue';
import { useConfigurationRevision } from '../composables/useConfigurationRevision';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const emit = defineEmits(['changed']);
const { t } = useI18n();
const copy = computed(() => ({
  APPROVAL_REQUIRED: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.CATALOG_REQUIRED'),
  APPROVAL_POLICY: t('JRC_CONTACT_CENTER.PAUSE_APPROVAL.CATALOG_POLICY'),
  HISTORY: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.HISTORY'),
  LOCAL_ONLY: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.LOCAL_ONLY'),
  GLOBAL_DENIED: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.GLOBAL_DENIED'),
  LOADING: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.LOADING'),
  LOAD_FAILED: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.LOAD_FAILED'),
  ENFORCED: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ENFORCED'),
  LEGACY: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.LEGACY'),
  CREATE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.CREATE'),
  DISABLE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.DISABLE'),
  ENABLE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ENABLE'),
  REFRESH: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.REFRESH'),
  NEW_PAUSES_ONLY: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.NEW_PAUSES_ONLY'),
  SEARCH: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.SEARCH'),
  STATUS: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.STATUS'),
  ALL: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ALL'),
  ACTIVE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ACTIVE'),
  INACTIVE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.INACTIVE'),
  EMPTY: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.EMPTY'),
  EDIT: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.EDIT'),
  PAGINATION: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.PAGINATION'),
  PREVIOUS: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.NEXT'),
  POLICY_TITLE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.POLICY_TITLE'),
  SAVE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.SAVE'),
  CANCEL: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.CANCEL'),
  ENABLE_REVIEW: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ENABLE_REVIEW'),
  DISABLE_REVIEW: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.DISABLE_REVIEW'),
  CONFIRM_ACTIVATION: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.CONFIRM_ACTIVATION'),
  CODE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.CODE'),
  NAME: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.NAME'),
  CATEGORY: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.CATEGORY'),
  DESCRIPTION: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.DESCRIPTION'),
  MINIMUM_MINUTES: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.MINIMUM_MINUTES'),
  DEFAULT_MINUTES: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.DEFAULT_MINUTES'),
  MAXIMUM_MINUTES: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.MAXIMUM_MINUTES'),
  UNITS: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.UNITS'),
  UNIT_INHERITANCE: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.UNIT_INHERITANCE'),
  PROFILES: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.PROFILES'),
  PROFILE_INHERITANCE: t(
    'JRC_CONTACT_CENTER.PAUSE_CATALOG.PROFILE_INHERITANCE'
  ),
  ACTIVE_FOR_NEW: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ACTIVE_FOR_NEW'),
  TIME_INFORMATION: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.TIME_INFORMATION'),
  INVALID_TIME: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.INVALID_TIME'),
  INVALID_FIELD: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.INVALID_FIELD'),
  TIME_PLACEHOLDER: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.TIME_PLACEHOLDER'),
  SAVE_FAILED: t('JRC_CONTACT_CENTER.PAUSE_CATALOG.SAVE_FAILED'),
  JUSTIFICATION_REQUIRED: t(
    'JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_REQUIRED'
  ),
  JUSTIFICATION_POLICY: t(
    'JRC_CONTACT_CENTER.PAUSE_CATALOG.JUSTIFICATION_POLICY'
  ),
}));
const text = key => copy.value[key];
const route = useRoute();
const router = useRouter();
const record = ref(null);
const loading = ref(false);
const failed = ref(false);
const saving = ref(false);
const error = ref('');
const invalid = ref([]);
const mode = ref('entry');
const editing = ref(null);
const input = ref({});
const enforced = ref(false);
const confirmed = ref(false);
const dialog = ref(null);
const canManage = computed(
  () =>
    props.context.capabilities?.configure &&
    props.context.capabilities?.configuration_global
);
const times = ['minimum_minutes', 'default_minutes', 'maximum_minutes'];
const parseMinutes = value => {
  if (value === '') return null;
  if (!/^\d{2}:[0-5]\d$/.test(value || '')) return NaN;
  const [hours, minutes] = value.split(':').map(Number);
  return hours * 60 + minutes;
};
const clock = value =>
  Number.isInteger(value)
    ? `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`
    : '';
const entry = computed(() => ({
  ...input.value,
  ...Object.fromEntries(
    times.map(field => [field, parseMinutes(input.value[field])])
  ),
}));
const draft = computed(() => {
  const entries = (record.value?.entries || []).map(row => ({ ...row }));
  if (mode.value === 'entry') {
    const index = entries.findIndex(row => row.code === editing.value);
    if (index < 0) entries.push(entry.value);
    else entries[index] = entry.value;
  }
  return {
    enforced:
      mode.value === 'policy'
        ? enforced.value
        : record.value?.enforced === true,
    entries,
  };
});
const revision = useConfigurationRevision({
  accountId: computed(() => props.accountId),
  resource: ref('pause_catalog'),
  draft,
});
const timeErrors = computed(() => {
  if (mode.value !== 'entry') return [];
  const values = entry.value;
  const errors = times.filter(field => Number.isNaN(values[field]));
  if (!Number.isInteger(values.default_minutes)) errors.push('default_minutes');
  [
    ['minimum_minutes', 'default_minutes'],
    ['default_minutes', 'maximum_minutes'],
    ['minimum_minutes', 'maximum_minutes'],
  ].forEach(([left, right]) => {
    if (
      Number.isInteger(values[left]) &&
      Number.isInteger(values[right]) &&
      values[left] > values[right]
    )
      errors.push(right);
  });
  return [...new Set(errors)];
});
const query = computed({
  get: () => String(route.query.pauses_q || ''),
  set: value =>
    router.replace({
      query: {
        ...route.query,
        pauses_q: value || undefined,
        pauses_page: undefined,
      },
    }),
});
const status = computed({
  get: () =>
    ['active', 'inactive'].includes(route.query.pauses_status)
      ? route.query.pauses_status
      : '',
  set: value =>
    router.replace({
      query: {
        ...route.query,
        pauses_status: value || undefined,
        pauses_page: undefined,
      },
    }),
});
const page = computed(() => {
  const value = Number(route.query.pauses_page || 1);
  return Number.isSafeInteger(value) && value > 0 ? value : 1;
});
const rows = computed(() =>
  (record.value?.entries || []).filter(row => {
    const matches = [row.name, row.code, row.category]
      .join(' ')
      .toLowerCase()
      .includes(query.value.toLowerCase());
    return (
      matches && (!status.value || row.active === (status.value === 'active'))
    );
  })
);
const pages = computed(() => Math.ceil(rows.value.length / 20));
const visibleRows = computed(() =>
  rows.value.slice((page.value - 1) * 20, page.value * 20)
);
const changePage = value =>
  router.replace({ query: { ...route.query, pauses_page: String(value) } });
const roles = computed(() => props.context.pause_catalog?.role_options || []);
const saveAllowed = computed(
  () =>
    canManage.value &&
    record.value &&
    revision.state.required &&
    revision.canSave.value &&
    !saving.value &&
    !timeErrors.value.length &&
    (mode.value !== 'policy' ||
      !enforced.value ||
      (confirmed.value && record.value.entries.some(row => row.active)))
);
let generation = 0;
let active = true;
const clearDialog = () => {
  revision.capture(null);
  input.value = {};
  invalid.value = [];
  error.value = '';
  confirmed.value = false;
};
const load = async () => {
  if (!active) return;
  generation += 1;
  const version = generation;
  record.value = null;
  failed.value = false;
  dialog.value?.close();
  clearDialog();
  if (!canManage.value) return;
  loading.value = true;
  try {
    const response = await API.pauseCatalog(props.accountId);
    if (!active || version !== generation) return;
    const value = response.data.item;
    if (
      String(value.id) !== String(props.accountId) ||
      !Array.isArray(value.entries) ||
      typeof value.enforced !== 'boolean'
    )
      throw new Error('Invalid catalog identity');
    record.value = value;
  } catch {
    if (active && version === generation) failed.value = true;
  } finally {
    if (active && version === generation) loading.value = false;
  }
};
const open = (row = null) => {
  if (!canManage.value || !record.value || saving.value) return;
  mode.value = 'entry';
  editing.value = row?.code || null;
  input.value = row
    ? {
        ...row,
        unit_ids: row.unit_ids.map(String),
        custom_role_ids: row.custom_role_ids.map(String),
      }
    : {
        code: '',
        name: '',
        category: '',
        description: '',
        active: false,
        justification_required: false,
        approval_required: false,
        unit_ids: [],
        custom_role_ids: [],
      };
  times.forEach(field => {
    input.value[field] = clock(row?.[field]);
  });
  invalid.value = [];
  error.value = '';
  revision.capture(record.value);
  dialog.value.open();
};
const openPolicy = () => {
  if (!canManage.value || !record.value || saving.value) return;
  mode.value = 'policy';
  enforced.value = !record.value.enforced;
  confirmed.value = false;
  error.value = '';
  invalid.value = [];
  revision.capture(record.value);
  dialog.value.open();
};
const save = async () => {
  if (!saveAllowed.value) return;
  const version = generation;
  saving.value = true;
  error.value = '';
  invalid.value = [];
  try {
    await API.updatePauseCatalog(props.accountId, draft.value, {
      ...revision.options(),
      activation_confirmed: mode.value === 'policy' && confirmed.value,
    });
    if (!active || version !== generation) return;
    saving.value = false;
    dialog.value.close();
    await load();
    if (active) emit('changed');
  } catch (failure) {
    if (!active || version !== generation) return;
    if (!revision.handleError(failure)) {
      invalid.value = failure.response?.data?.invalid_attributes || [];
      error.value = text('SAVE_FAILED');
    }
  } finally {
    if (active && version === generation) saving.value = false;
  }
};
watch(() => [String(props.accountId), canManage.value], load, {
  immediate: true,
});
watch([pages, loading], () => {
  if (record.value && !loading.value && page.value > Math.max(1, pages.value))
    changePage(1);
});
onBeforeUnmount(() => {
  active = false;
  generation += 1;
  dialog.value?.close();
});
</script>

<template>
  <div class="min-w-0 space-y-4" data-pause-catalog>
    <AgentStateHistory :account-id="accountId" :context="context" />
    <RouterLink
      v-if="context.capabilities.configuration_audit"
      :to="{
        name: 'jrc_contact_center_admin_section',
        params: { accountId, section: 'audit' },
        query: {
          ...route.query,
          audit_source: 'configuration',
          audit_config_resource_type: 'pause_catalog',
          audit_config_resource_id: String(accountId),
          audit_config_history: 'true',
        },
      }"
      class="inline-block rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
      data-pause-catalog-history
    >
      {{ text('HISTORY') }}
    </RouterLink>
    <p
      class="rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm text-n-amber-11"
    >
      {{ text('LOCAL_ONLY') }}
    </p>
    <p v-if="!canManage" class="text-sm text-n-amber-11" role="status">
      {{ text('GLOBAL_DENIED') }}
    </p>
    <p v-else-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ text('LOADING') }}
    </p>
    <p v-else-if="failed" role="alert" class="text-sm text-n-ruby-11">
      {{ text('LOAD_FAILED') }}
    </p>
    <template v-else-if="record">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <p class="text-sm text-n-slate-11">
          {{ record.enforced ? text('ENFORCED') : text('LEGACY') }}
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white"
            type="button"
            @click="open()"
          >
            {{ text('CREATE') }}
          </button>
          <button
            class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
            type="button"
            @click="openPolicy()"
          >
            {{ record.enforced ? text('DISABLE') : text('ENABLE') }}
          </button>
          <button
            class="rounded-lg border border-n-weak px-3 py-2 text-sm text-n-slate-12"
            type="button"
            @click="load()"
          >
            {{ text('REFRESH') }}
          </button>
        </div>
      </div>
      <p class="text-xs text-n-slate-10">
        {{ text('NEW_PAUSES_ONLY') }}
      </p>
      <div class="grid min-w-0 gap-3 sm:grid-cols-2">
        <label class="min-w-0 text-sm text-n-slate-12">
          {{ text('SEARCH') }}
          <input
            v-model="query"
            type="search"
            class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2 aria-invalid:border-n-ruby-8"
          />
        </label>
        <label class="min-w-0 text-sm text-n-slate-12">
          {{ text('STATUS') }}
          <select
            v-model="status"
            class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">
              {{ text('ALL') }}
            </option>
            <option value="active">
              {{ text('ACTIVE') }}
            </option>
            <option value="inactive">
              {{ text('INACTIVE') }}
            </option>
          </select>
        </label>
      </div>
      <p v-if="!rows.length" class="text-sm text-n-slate-11">
        {{ text('EMPTY') }}
      </p>
      <article
        v-for="row in visibleRows"
        :key="row.code"
        class="flex min-w-0 flex-wrap items-start justify-between gap-3 rounded-xl border border-n-weak p-3"
      >
        <div class="min-w-0 break-words">
          <h3 class="font-medium text-n-slate-12">
            {{ row.name }}
          </h3>
          <p class="text-sm text-n-slate-11">
            {{
              t('JRC_CONTACT_CENTER.PAUSE_CATALOG.ROW_DETAIL', {
                code: row.code,
                category: row.category,
              })
            }}
          </p>
          <p class="text-sm text-n-slate-11">
            {{
              t('JRC_CONTACT_CENTER.PAUSE_CATALOG.TIME_DETAIL', {
                time: clock(row.default_minutes),
                status: row.active ? text('ACTIVE') : text('INACTIVE'),
              })
            }}
          </p>
        </div>
        <button
          class="rounded-lg border border-n-blue-6 px-3 py-2 text-sm text-n-blue-11"
          type="button"
          @click="open(row)"
        >
          {{ text('EDIT') }}
        </button>
      </article>
      <nav
        v-if="pages > 1"
        class="flex flex-wrap items-center gap-3"
        :aria-label="text('PAGINATION')"
      >
        <button
          type="button"
          :disabled="page <= 1"
          @click="changePage(page - 1)"
        >
          {{ text('PREVIOUS') }}
        </button>
        <span class="text-sm text-n-slate-11">
          {{
            t('JRC_CONTACT_CENTER.PAUSE_CATALOG.PAGE_DETAIL', { page, pages })
          }}
        </span>
        <button
          type="button"
          :disabled="page >= pages"
          @click="changePage(page + 1)"
        >
          {{ text('NEXT') }}
        </button>
      </nav>
    </template>
    <Dialog
      ref="dialog"
      contained
      overflow-y-auto
      width="2xl"
      :title="
        mode === 'policy'
          ? text('POLICY_TITLE')
          : text(editing ? 'EDIT' : 'CREATE')
      "
      :confirm-button-label="text('SAVE')"
      :cancel-button-label="text('CANCEL')"
      :disable-confirm-button="!saveAllowed"
      :is-loading="saving"
      :dismissible="!saving"
      :close-on-click-outside="false"
      @confirm="save"
      @close="clearDialog"
    >
      <div class="grid min-w-0 gap-4 sm:grid-cols-2">
        <ConfigurationRevisionConflict
          :state="revision.state"
          :draft="draft"
          resource="pause_catalog"
          :reviewed="revision.reviewed()"
          @reload="revision.reload"
          @review="revision.review"
        />
        <p
          v-if="error"
          role="alert"
          class="text-sm text-n-ruby-11 sm:col-span-2"
        >
          {{ error }}
        </p>
        <template v-if="mode === 'policy'">
          <p class="text-sm text-n-slate-12 sm:col-span-2">
            {{ enforced ? text('ENABLE_REVIEW') : text('DISABLE_REVIEW') }}
          </p>
          <label
            v-if="enforced"
            class="flex items-start gap-2 text-sm text-n-slate-12 sm:col-span-2"
          >
            <input v-model="confirmed" type="checkbox" />
            {{ text('CONFIRM_ACTIVATION') }}
          </label>
        </template>
        <template v-else>
          <label
            v-for="field in ['code', 'name', 'category']"
            :key="field"
            class="min-w-0 text-sm text-n-slate-12"
          >
            {{ text(field.toUpperCase()) }}
            <input
              v-model.trim="input[field]"
              required
              :disabled="field === 'code' && Boolean(editing)"
              :aria-label="text(field.toUpperCase())"
              :maxlength="field === 'code' ? 64 : field === 'name' ? 100 : 60"
              :aria-invalid="invalid.includes(field) || undefined"
              class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2 aria-invalid:border-n-ruby-8"
            />
            <span
              v-if="invalid.includes(field)"
              role="alert"
              :data-pause-invalid-field="field"
              class="mt-1 block text-xs text-n-ruby-11"
            >
              {{ text('INVALID_FIELD') }}
            </span>
          </label>
          <label class="min-w-0 text-sm text-n-slate-12 sm:col-span-2">
            {{ text('DESCRIPTION') }}
            <textarea
              v-model="input.description"
              :aria-invalid="invalid.includes('description') || undefined"
              maxlength="1000"
              class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2 aria-invalid:border-n-ruby-8"
            />
            <span
              v-if="invalid.includes('description')"
              role="alert"
              data-pause-invalid-field="description"
              class="mt-1 block text-xs text-n-ruby-11"
            >
              {{ text('INVALID_FIELD') }}
            </span>
          </label>
          <label
            v-for="field in times"
            :key="field"
            class="min-w-0 text-sm text-n-slate-12"
          >
            {{ text(field.toUpperCase()) }}
            <input
              v-model="input[field]"
              :aria-label="text(field.toUpperCase())"
              :required="field === 'default_minutes'"
              pattern="[0-9]{2}:[0-5][0-9]"
              :placeholder="text('TIME_PLACEHOLDER')"
              :aria-invalid="
                timeErrors.includes(field) ||
                invalid.includes(field) ||
                undefined
              "
              class="mt-1 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
            <span
              v-if="timeErrors.includes(field) || invalid.includes(field)"
              class="mt-1 block text-xs text-n-ruby-11"
            >
              {{ text('INVALID_TIME') }}
            </span>
          </label>
          <label
            class="flex min-w-0 items-start gap-2 text-sm text-n-slate-12 sm:col-span-2"
          >
            <input
              v-model="input.justification_required"
              type="checkbox"
              :aria-invalid="
                invalid.includes('justification_required') || undefined
              "
            />
            <span>
              {{ text('JUSTIFICATION_REQUIRED') }}
              <span class="mt-1 block text-xs text-n-slate-10">{{
                text('JUSTIFICATION_POLICY')
              }}</span>
            </span>
          </label>
          <label
            class="flex min-w-0 items-start gap-2 text-sm text-n-slate-12 sm:col-span-2"
          >
            <input
              v-model="input.approval_required"
              type="checkbox"
              :aria-invalid="invalid.includes('approval_required') || undefined"
            />
            <span class="space-y-1">
              <span class="block">{{ text('APPROVAL_REQUIRED') }}</span>
              <span class="block text-xs text-n-slate-10">{{
                text('APPROVAL_POLICY')
              }}</span>
            </span>
          </label>
          <label class="min-w-0 text-sm text-n-slate-12">
            {{ text('UNITS') }}
            <select
              v-model="input.unit_ids"
              :aria-label="text('UNITS')"
              multiple
              class="mt-1 h-32 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option
                v-for="unit in context.units"
                :key="unit.id"
                :value="String(unit.id)"
              >
                {{ unit.name }}
              </option>
            </select>
            <span class="text-xs text-n-slate-10">
              {{ text('UNIT_INHERITANCE') }}
            </span>
          </label>
          <label class="min-w-0 text-sm text-n-slate-12">
            {{ text('PROFILES') }}
            <select
              v-model="input.custom_role_ids"
              :aria-label="text('PROFILES')"
              multiple
              :disabled="!roles.length"
              class="mt-1 h-32 w-full min-w-0 rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option
                v-for="role in roles"
                :key="role.id"
                :value="String(role.id)"
              >
                {{ role.name }}
              </option>
            </select>
            <span class="text-xs text-n-slate-10">
              {{ text('PROFILE_INHERITANCE') }}
            </span>
          </label>
          <label
            class="flex items-center gap-2 text-sm text-n-slate-12 sm:col-span-2"
          >
            <input v-model="input.active" type="checkbox" />
            {{ text('ACTIVE_FOR_NEW') }}
          </label>
          <p class="text-xs text-n-slate-11 sm:col-span-2">
            {{ text('TIME_INFORMATION') }}
          </p>
        </template>
      </div>
    </Dialog>
  </div>
</template>
