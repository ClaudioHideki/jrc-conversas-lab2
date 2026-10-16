<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TelephonyIntegrationAPI from 'dashboard/api/telephonyIntegration';

const { t } = useI18n();
const defaults = () => ({
  enabled: false,
  sync_enabled: false,
  provider: 'pabx_v1',
  base_url: '',
  allow_http_lab: false,
  expected_tenant: '',
  test_extension: '',
  technical_identity: 'plain',
  timeout_seconds: 15,
  interval_seconds: 300,
  window_days: 7,
  overlap_seconds: 120,
  token_path: 'token',
  cdr_rows_path: '',
  cdr_total_path: 'data.total',
  cdr_extension_identity: 'plain',
  cdr_page_parameter: '',
  cdr_page_size: 20,
  cdr_timezone: 'UTC',
  recording_lookup: '',
});
const form = reactive(defaults());
const username = ref('');
const password = ref('');
const mapping = ref('{}');
const busy = ref(false);
const feedback = ref('');
const saved = ref('');
const configured = ref(false);
const diagnostic = ref(null);
const sync = ref({});
const snapshot = () =>
  JSON.stringify([form, mapping.value, username.value, password.value]);
const dirty = computed(() => snapshot() !== saved.value);
const fields = computed(() => [
  { key: 'base_url', label: t('SOFTPHONE.PABX.BASE_URL'), type: 'url' },
  { key: 'expected_tenant', label: t('SOFTPHONE.PABX.TENANT'), type: 'text' },
  { key: 'test_extension', label: t('SOFTPHONE.PABX.EXTENSION'), type: 'text' },
  { key: 'token_path', label: t('SOFTPHONE.PABX.TOKEN_PATH'), type: 'text' },
  { key: 'cdr_rows_path', label: t('SOFTPHONE.PABX.ROWS_PATH'), type: 'text' },
  {
    key: 'cdr_page_parameter',
    label: t('SOFTPHONE.PABX.CDR_PAGE_PARAMETER'),
    type: 'text',
  },
  {
    key: 'cdr_timezone',
    label: t('SOFTPHONE.PABX.CDR_TIMEZONE'),
    type: 'text',
  },
  {
    key: 'cdr_total_path',
    label: t('SOFTPHONE.PABX.TOTAL_PATH'),
    type: 'text',
  },
]);
const limits = computed(() => [
  {
    key: 'timeout_seconds',
    label: t('SOFTPHONE.PABX.TIMEOUT'),
    min: 1,
    max: 30,
  },
  {
    key: 'interval_seconds',
    label: t('SOFTPHONE.PABX.INTERVAL'),
    min: 60,
    max: 86400,
  },
  { key: 'window_days', label: t('SOFTPHONE.PABX.WINDOW'), min: 1, max: 31 },
  {
    key: 'overlap_seconds',
    label: t('SOFTPHONE.PABX.OVERLAP'),
    min: 0,
    max: 600,
  },
]);
const verificationLabel = computed(() => {
  if (diagnostic.value?.overall === 'checks_passed')
    return t('SOFTPHONE.PABX.CHECK_PASSED');
  if (diagnostic.value?.overall === 'blocked_scope')
    return t('SOFTPHONE.PABX.CHECK_BLOCKED');
  return t('SOFTPHONE.PABX.CHECK_PARTIAL');
});
const diagnosticRows = computed(() =>
  diagnostic.value
    ? [
        [t('SOFTPHONE.PABX.OVERALL'), verificationLabel.value],
        [t('SOFTPHONE.PABX.API'), diagnostic.value.api],
        [t('SOFTPHONE.PABX.AUTHENTICATION'), diagnostic.value.authentication],
        [t('SOFTPHONE.PABX.TENANT'), diagnostic.value.expected_tenant],
        [
          t('SOFTPHONE.PABX.RETURNED_TENANT'),
          diagnostic.value.returned_accountcode,
        ],
        [t('SOFTPHONE.PABX.EXTENSION'), diagnostic.value.extension],
        [
          t('SOFTPHONE.PABX.TECHNICAL_EXTENSION'),
          diagnostic.value.technical_extension,
        ],
        [
          t('SOFTPHONE.PABX.TECHNICAL_STATUS'),
          diagnostic.value.technical_status,
        ],
        [
          t('SOFTPHONE.PABX.EXTENSION_REGISTRY'),
          diagnostic.value.extension_registry,
        ],
        [t('SOFTPHONE.PABX.EXTENSIONS_LIST'), diagnostic.value.extensions_list],
        [
          t('SOFTPHONE.PABX.EXTENSION_SEARCH'),
          diagnostic.value.extension_search,
        ],
        [
          t('SOFTPHONE.PABX.COLLABORATOR'),
          diagnostic.value.collaborators?.map(user => user.name).join(', '),
        ],
        [t('SOFTPHONE.PABX.CDR'), diagnostic.value.cdr],
        [t('SOFTPHONE.PABX.RECORDINGS'), diagnostic.value.recordings],
        [t('SOFTPHONE.PABX.LAST_CHECK'), diagnostic.value.checked_at],
        [t('SOFTPHONE.PABX.ERROR'), diagnostic.value.error],
      ]
    : []
);

const apply = data => {
  Object.assign(form, defaults(), data.settings);
  mapping.value = JSON.stringify(data.settings.cdr_fields || {}, null, 2);
  configured.value = data.configured;
  diagnostic.value = data.sync.diagnostic || null;
  sync.value = data.sync;
  username.value = '';
  password.value = '';
  saved.value = snapshot();
};
const run = async action => {
  if (busy.value) return;
  busy.value = true;
  feedback.value = '';
  try {
    await action();
  } catch {
    feedback.value = t('SOFTPHONE.PABX.FAILED');
  } finally {
    busy.value = false;
  }
};
const load = () =>
  run(async () => apply((await TelephonyIntegrationAPI.get()).data));
const save = () =>
  run(async () => {
    const settings = Object.fromEntries(
      Object.entries(form).filter(([, value]) => value !== '')
    );
    settings.cdr_fields = JSON.parse(mapping.value);
    apply(
      (
        await TelephonyIntegrationAPI.save({
          settings,
          api_username: username.value,
          api_password: password.value,
        })
      ).data
    );
    feedback.value = t('SOFTPHONE.PABX.SAVED');
  });
const testConnection = () =>
  run(async () => {
    diagnostic.value = null;
    diagnostic.value = (await TelephonyIntegrationAPI.testConnection()).data;
  });
const synchronize = () =>
  run(async () => {
    await TelephonyIntegrationAPI.synchronize();
    feedback.value = t('SOFTPHONE.PABX.QUEUED');
  });
onMounted(load);
</script>

<template>
  <section
    class="mb-6 space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-5"
  >
    <h2 class="text-xl font-semibold">{{ t('SOFTPHONE.PABX.TITLE') }}</h2>
    <p class="text-sm text-n-slate-11">{{ t('SOFTPHONE.PABX.HELP') }}</p>
    <p class="rounded-lg bg-n-amber-3 p-3 text-sm text-n-amber-11">
      {{ t('SOFTPHONE.PABX.PENDING') }}
    </p>
    <p
      v-if="form.base_url.startsWith('http://')"
      role="alert"
      class="text-sm text-n-ruby-11"
    >
      {{ t('SOFTPHONE.PABX.HTTP_WARNING') }}
    </p>
    <form class="space-y-4" @submit.prevent="save">
      <fieldset :disabled="busy" class="space-y-4">
        <label class="block text-sm">
          <span>{{ t('SOFTPHONE.PABX.CDR_IDENTITY') }}</span>
          <select
            v-model="form.cdr_extension_identity"
            data-testid="cdr-identity"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="plain">{{ t('SOFTPHONE.PABX.PLAIN') }}</option>
            <option value="tenant_prefix">
              {{ t('SOFTPHONE.PABX.PREFIX') }}
            </option>
          </select>
        </label>
        <p class="text-xs text-n-slate-11">
          {{ t('SOFTPHONE.PABX.CDR_CONTRACT_HELP') }}
        </p>
        <label class="flex gap-2">
          <input v-model="form.enabled" type="checkbox" /><span>{{
            t('SOFTPHONE.PABX.ENABLED')
          }}</span>
        </label>
        <div class="grid gap-4 md:grid-cols-2">
          <label v-for="field in fields" :key="field.key" class="text-sm">
            <span>{{ field.label }}</span>
            <input
              v-model="form[field.key]"
              :type="field.type"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
          <label class="text-sm">
            <span>{{ t('SOFTPHONE.PABX.USERNAME') }}</span>
            <input
              v-model="username"
              autocomplete="off"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
          <label class="text-sm">
            <span>{{ t('SOFTPHONE.PABX.PASSWORD') }}</span>
            <input
              v-model="password"
              type="password"
              autocomplete="new-password"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
          <label class="text-sm">
            <span>{{ t('SOFTPHONE.PABX.IDENTITY') }}</span>
            <select
              v-model="form.technical_identity"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="plain">{{ t('SOFTPHONE.PABX.PLAIN') }}</option>
              <option value="tenant_prefix">
                {{ t('SOFTPHONE.PABX.PREFIX') }}
              </option>
            </select>
          </label>
          <label v-for="limit in limits" :key="limit.key" class="text-sm">
            <span>{{ limit.label }}</span>
            <input
              v-model.number="form[limit.key]"
              type="number"
              :min="limit.min"
              :max="limit.max"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
            />
          </label>
        </div>
        <label class="flex gap-2">
          <input v-model="form.allow_http_lab" type="checkbox" /><span>{{
            t('SOFTPHONE.PABX.ALLOW_HTTP')
          }}</span>
        </label>
        <label class="block text-sm">
          <span>{{ t('SOFTPHONE.PABX.MAPPING') }}</span>
          <textarea
            v-model="mapping"
            rows="5"
            spellcheck="false"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 font-mono"
          />
        </label>
        <label class="block text-sm">
          <span>{{ t('SOFTPHONE.PABX.RECORDING_LOOKUP') }}</span>
          <select
            v-model="form.recording_lookup"
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-1 p-2"
          >
            <option value="">{{ t('SOFTPHONE.PABX.NOT_CONFIGURED') }}</option>
            <option value="link">{{ t('SOFTPHONE.PABX.BY_LINK') }}</option>
            <option
              v-if="['uniqueId', 'gravacao'].includes(form.recording_lookup)"
              :value="form.recording_lookup"
              disabled
            >
              {{ t('SOFTPHONE.PABX.RECORDING_PENDING') }}
            </option>
          </select>
        </label>
        <label class="flex gap-2">
          <input v-model="form.sync_enabled" type="checkbox" /><span>{{
            t('SOFTPHONE.PABX.SYNC_ENABLED')
          }}</span>
        </label>
        <p class="text-xs text-n-slate-11">
          {{ t('SOFTPHONE.PABX.SAVE_FIRST') }}
        </p>
        <div class="flex flex-wrap gap-3">
          <button
            type="submit"
            class="rounded-lg bg-n-brand px-4 py-2 text-white"
          >
            {{ t('SOFTPHONE.PABX.SAVE') }}
          </button>
          <button
            type="button"
            :disabled="!configured || dirty"
            class="rounded-lg border border-n-weak px-4 py-2 disabled:opacity-50"
            @click="testConnection"
          >
            {{ t('SOFTPHONE.PABX.TEST') }}
          </button>
          <button
            type="button"
            :disabled="
              !configured || dirty || !form.enabled || !form.sync_enabled
            "
            class="rounded-lg border border-n-weak px-4 py-2 disabled:opacity-50"
            @click="synchronize"
          >
            {{ t('SOFTPHONE.PABX.SYNC') }}
          </button>
        </div>
      </fieldset>
    </form>
    <p v-if="feedback" role="status" class="text-sm">{{ feedback }}</p>
    <p
      v-if="diagnostic?.tenant_compatible === false"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 font-medium text-n-ruby-11"
    >
      {{ t('SOFTPHONE.PABX.TENANT_MISMATCH') }}
    </p>
    <dl class="grid gap-2 text-sm md:grid-cols-2">
      <div
        v-for="[label, value] in diagnosticRows"
        :key="label"
        class="flex justify-between gap-3 rounded-lg bg-n-alpha-2 p-2"
      >
        <dt>{{ label }}</dt>
        <dd class="break-all">{{ value ?? '—' }}</dd>
      </div>
      <div class="flex justify-between gap-3 p-2">
        <dt>{{ t('SOFTPHONE.PABX.LAST_SUCCESS') }}</dt>
        <dd>{{ sync.last_success_at || '—' }}</dd>
      </div>
      <div class="flex justify-between gap-3 p-2">
        <dt>{{ t('SOFTPHONE.PABX.ERROR') }}</dt>
        <dd>{{ sync.last_error || '—' }}</dd>
      </div>
    </dl>
  </section>
</template>
