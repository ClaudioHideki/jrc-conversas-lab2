<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { signatureIntegrationAPI } from 'dashboard/api/crm/commercialCycle';
import { moduleTabClasses } from 'dashboard/components-next/navigation/moduleTabClasses';
import { useBackofficePresentation } from './useBackofficePresentation';

const route = useRoute();
const store = useStore();
const { text } = useBackofficePresentation();
const copy = key => text(`SIGNATURE.${key}`);
const tabs = ['connection', 'checks'];
const tab = ref('connection');
const record = ref(null);
const loading = ref(false);
const saving = ref(false);
const checking = ref(false);
const error = ref('');
const message = ref('');
const form = reactive({});
const privateKey = ref('');
const connectKeys = ref('');
const identity = computed(
  () => `${route.params.accountId}:${store.getters.getCurrentUser?.id}`
);
const fields = [
  'integration_key',
  'impersonated_user_id',
  'external_account_id',
];
let sequence = 0;
let controller;
let original = '';
const dirty = computed(
  () =>
    !!privateKey.value ||
    !!connectKeys.value ||
    JSON.stringify(form) !== original
);
const busy = computed(() => loading.value || saving.value || checking.value);
const reset = () => {
  record.value = null;
  privateKey.value = '';
  connectKeys.value = '';
  Object.assign(form, {
    environment: 'demo',
    integration_key: '',
    impersonated_user_id: '',
    external_account_id: '',
    enabled: false,
  });
  original = JSON.stringify(form);
};
const apply = data => {
  reset();
  record.value = data;
  if (data.details) Object.assign(form, data.details);
  original = JSON.stringify(form);
};
const failureMessage = failure => {
  const code = failure.response?.data?.code;
  const known = [
    'CONFIGURATION_CHANGED',
    'CONSENT_REQUIRED',
    'CREDENTIAL_INVALID',
    'CREDENTIAL_UNAVAILABLE',
    'ACCOUNT_NOT_AUTHORIZED',
    'AUTHORIZATION_INVALID',
    'PROVIDER_REJECTED',
    'PROVIDER_UNAVAILABLE',
    'PROVIDER_RESPONSE_INVALID',
  ];
  if ([401, 403].includes(failure.response?.status))
    return copy('ERROR_DENIED');
  return copy(known.includes(code) ? `ERROR_${code}` : 'ERROR_GENERIC');
};
const load = async () => {
  controller?.abort();
  controller = new AbortController();
  sequence += 1;
  const current = sequence;
  reset();
  error.value = '';
  message.value = '';
  saving.value = false;
  checking.value = false;
  loading.value = true;
  try {
    const { data } = await signatureIntegrationAPI.showForAccount(
      route.params.accountId,
      { signal: controller.signal }
    );
    if (current === sequence) apply(data);
  } catch (failure) {
    if (current === sequence) error.value = failureMessage(failure);
  } finally {
    if (current === sequence) loading.value = false;
  }
};
const execute = async check => {
  if (busy.value || !record.value?.can_manage) return;
  const current = sequence;
  const accountId = route.params.accountId;
  error.value = '';
  message.value = '';
  if (check) checking.value = true;
  else saving.value = true;
  try {
    const operation = check
      ? signatureIntegrationAPI.checkForAccount(
          accountId,
          record.value.revision
        )
      : signatureIntegrationAPI.saveForAccount(accountId, {
          revision: record.value.revision,
          integration: {
            ...form,
            ...(privateKey.value ? { private_key: privateKey.value } : {}),
            ...(connectKeys.value
              ? {
                  connect_hmac_keys: connectKeys.value
                    .split('\n')
                    .map(value => value.trim())
                    .filter(Boolean),
                }
              : {}),
          },
        });
    const { data } = await operation;
    if (current !== sequence) return;
    apply(data);
    message.value = copy(check ? 'AUTH_CHECKED' : 'SAVED');
  } catch (failure) {
    if (current === sequence) {
      if ([401, 403, 404].includes(failure.response?.status)) reset();
      error.value = failureMessage(failure);
    }
  } finally {
    if (current === sequence) {
      saving.value = false;
      checking.value = false;
    }
  }
};
watch(identity, load, { immediate: true });
onBeforeUnmount(() => {
  sequence += 1;
  controller?.abort();
  reset();
});
</script>

<template>
  <section class="mx-auto max-w-4xl space-y-4" :aria-busy="busy">
    <header class="rounded-xl border border-n-violet-6 bg-n-violet-3 p-5">
      <h2 class="text-xl font-bold text-n-violet-12">{{ copy('TITLE') }}</h2>
      <p class="mt-2 text-sm text-n-slate-11">{{ copy('DESCRIPTION') }}</p>
    </header>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg border border-n-ruby-6 bg-n-ruby-3 p-4 text-sm text-n-ruby-12"
    >
      {{ error }}
    </p>
    <p
      v-if="message"
      role="status"
      class="rounded-lg border border-n-teal-6 bg-n-teal-3 p-4 text-sm text-n-teal-12"
    >
      {{ message }}
    </p>
    <p v-if="loading" role="status">{{ text('LOADING') }}</p>
    <template v-else-if="record">
      <nav class="flex gap-2" :aria-label="copy('TITLE')">
        <button
          v-for="key in tabs"
          :key="key"
          :class="moduleTabClasses('violet', tab === key)"
          :aria-pressed="tab === key"
          @click="tab = key"
        >
          {{ copy(`TAB_${key}`) }}
        </button>
      </nav>
      <form
        v-if="tab === 'connection' && record.can_manage"
        class="space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-5"
        @submit.prevent="execute(false)"
      >
        <fieldset :disabled="busy" class="grid gap-4 md:grid-cols-2">
          <label class="text-sm font-semibold">
            <span>{{ copy('ENVIRONMENT') }}</span>
            <select
              v-model="form.environment"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 text-n-slate-12"
            >
              <option value="demo">{{ copy('DEMO') }}</option>
              <option value="production">{{ copy('PRODUCTION') }}</option>
            </select>
          </label>
          <label class="flex items-center gap-2 text-sm font-semibold">
            <input v-model="form.enabled" type="checkbox" />
            <span>{{ copy('ENABLED') }}</span>
          </label>
          <label v-for="key in fields" :key="key" class="text-sm font-semibold">
            <span>{{ copy(key) }}</span>
            <input
              v-model="form[key]"
              required
              maxlength="36"
              autocomplete="off"
              spellcheck="false"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 font-mono text-n-slate-12"
            />
          </label>
          <label class="text-sm font-semibold">
            <span>{{ copy('PRIVATE_KEY') }}</span>
            <textarea
              v-model="privateKey"
              rows="3"
              :required="!record.configured"
              maxlength="16384"
              autocomplete="off"
              spellcheck="false"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 font-mono text-n-slate-12"
            />
          </label>
          <label class="text-sm font-semibold">
            <span>{{ copy('CONNECT_KEYS') }}</span>
            <textarea
              v-model="connectKeys"
              rows="2"
              :required="!record.configured"
              maxlength="1285"
              autocomplete="off"
              spellcheck="false"
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 font-mono text-n-slate-12"
            />
          </label>
        </fieldset>
        <p class="text-xs text-n-slate-11">{{ copy('SECRET_HELP') }}</p>
        <button
          type="submit"
          :disabled="busy || !dirty"
          class="rounded-lg bg-n-violet-9 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {{ copy('SAVE') }}
        </button>
      </form>
      <div
        v-else-if="tab === 'connection'"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-5 text-sm"
      >
        {{ copy('MANAGER_ONLY') }}
      </div>
      <div
        v-else
        class="space-y-4 rounded-xl border border-n-weak bg-n-solid-2 p-5"
      >
        <dl class="grid gap-3 text-sm md:grid-cols-3">
          <div>
            <dt class="text-n-slate-11">{{ copy('CONFIGURATION') }}</dt>
            <dd class="mt-1 font-semibold">
              {{ copy(record.configured ? 'RECORDED' : 'NOT_CONFIGURED') }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">{{ copy('OAUTH') }}</dt>
            <dd class="mt-1 font-semibold">
              {{
                copy(record.authorization_checked ? 'VERIFIED' : 'NOT_VERIFIED')
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">{{ copy('CONNECT') }}</dt>
            <dd class="mt-1 font-semibold">
              {{ copy(record.connect_checked ? 'VERIFIED' : 'NOT_VERIFIED') }}
            </dd>
          </div>
        </dl>
        <p class="text-sm text-n-slate-11">{{ copy('CHECK_HELP') }}</p>
        <template v-if="record.can_manage">
          <label v-if="record.connect_url" class="block text-sm font-semibold">
            <span>{{ copy('CONNECT_URL') }}</span>
            <input
              :value="record.connect_url"
              readonly
              class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2 font-mono text-xs text-n-slate-12"
            />
          </label>
          <p v-else class="text-sm text-n-amber-11">
            {{ copy('HTTPS_REQUIRED') }}
          </p>
          <button
            :disabled="busy || !record.configured || !record.enabled || dirty"
            class="rounded-lg bg-n-violet-9 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            @click="execute(true)"
          >
            {{ copy('CHECK_AUTH') }}
          </button>
        </template>
        <button
          :disabled="busy"
          class="ml-2 rounded-lg border border-n-weak px-4 py-2 text-sm disabled:opacity-50"
          @click="load"
        >
          {{ text('REFRESH') }}
        </button>
      </div>
    </template>
  </section>
</template>
