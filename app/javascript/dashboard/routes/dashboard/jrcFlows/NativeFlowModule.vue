<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { createJrcFlowNativeApi } from 'dashboard/api/jrcFlowNative';
import { nativeEditorBuild } from './nativeEditorBuild';
import messages from './workspace.en.json';

const { t } = useI18n({
  useScope: 'local',
  messages: { en: messages, pt_BR: messages, pt: messages },
});
const { accountId, accountScopedRoute } = useAccount();
const store = useStore();
const administrator = computed(
  () =>
    store.getters.getCurrentRole === 'administrator' &&
    !store.getters.getCurrentCustomRoleId
);
const inboxes = ref([]);
const selected = ref([]);
const configuration = ref(null);
const registration = ref(null);
const session = ref(null);
const origin = ref('');
const credential = ref('');
const challenge = ref('');
const transferNonce = ref('');
const busy = ref(false);
const error = ref('');
const notice = ref('');
const editorElement = ref(null);
const installationGrant = ref('');
const installationTransfer = ref('');
const installation = ref(null);
const errorMessages = computed(() => ({
  FLOW_CAPABILITY_NOT_GRANTED: t('NATIVE.ERRORS.FLOW_CAPABILITY_NOT_GRANTED'),
  FLOW_MEMBERSHIP_REQUIRED: t('NATIVE.ERRORS.FLOW_MEMBERSHIP_REQUIRED'),
  FLOW_FEATURE_DISABLED: t('NATIVE.ERRORS.FLOW_FEATURE_DISABLED'),
  FLOW_NATIVE_CONFIGURATION_REQUIRED: t(
    'NATIVE.ERRORS.FLOW_NATIVE_CONFIGURATION_REQUIRED'
  ),
  FLOW_NATIVE_REGISTRATION_REQUIRED: t(
    'NATIVE.ERRORS.FLOW_NATIVE_REGISTRATION_REQUIRED'
  ),
  FLOW_REGISTRATION_IN_PROGRESS: t(
    'NATIVE.ERRORS.FLOW_REGISTRATION_IN_PROGRESS'
  ),
  FLOW_REGISTRATION_REVOKE_REQUIRED: t(
    'NATIVE.ERRORS.FLOW_REGISTRATION_REVOKE_REQUIRED'
  ),
  FLOW_ORIGIN_NATIVE_EVIDENCE_REQUIRED: t(
    'NATIVE.ERRORS.FLOW_ORIGIN_NATIVE_EVIDENCE_REQUIRED'
  ),
  FLOW_ORIGIN_CAPABILITY_REQUIRED: t(
    'NATIVE.ERRORS.FLOW_ORIGIN_CAPABILITY_REQUIRED'
  ),
  FLOW_HOST_FENCE_REQUIRED: t('NATIVE.ERRORS.FLOW_HOST_FENCE_REQUIRED'),
  FLOW_BROKER_UNAVAILABLE: t('NATIVE.ERRORS.FLOW_BROKER_UNAVAILABLE'),
}));
let api;
let abort;
let generation = 0;
let unmountEditor;
async function action(work) {
  const current = generation;
  busy.value = true;
  error.value = '';
  notice.value = '';
  try {
    await work(current);
  } catch (reason) {
    if (current === generation) {
      const code = reason.response?.data?.code;
      error.value = errorMessages.value[code] || t('NATIVE.ERRORS.DEFAULT');
    }
  } finally {
    if (current === generation) busy.value = false;
  }
}
async function load() {
  generation += 1;
  abort?.abort();
  abort = new AbortController();
  unmountEditor?.();
  unmountEditor = undefined;
  installation.value = null;
  installationGrant.value = '';
  installationTransfer.value = '';
  credential.value = '';
  transferNonce.value = '';
  challenge.value = '';
  origin.value = '';
  inboxes.value = [];
  selected.value = [];
  session.value = null;
  registration.value = null;
  configuration.value = null;
  api = createJrcFlowNativeApi(accountId.value);
  await action(async current => {
    const values = await api.inboxes(abort.signal);
    if (current !== generation) return;
    inboxes.value = values;
    if (administrator.value) {
      const result = await api.configuration(abort.signal);
      if (current !== generation) return;
      configuration.value = result;
      origin.value = result.brokerOrigin || '';
    }
  });
}
async function configure() {
  await action(async current => {
    try {
      const result = await api.configure(
        origin.value,
        credential.value,
        abort.signal
      );
      if (current === generation) {
        configuration.value = result;
        notice.value = t('NATIVE.NOTICES.CONFIGURED');
      }
    } finally {
      credential.value = '';
    }
  });
}
async function register() {
  await action(async current => {
    const result = await api.register(
      challenge.value,
      transferNonce.value,
      selected.value,
      abort.signal
    );
    if (current !== generation) return;
    registration.value = result;
    transferNonce.value = '';
    notice.value = t('NATIVE.NOTICES.REGISTERED');
  });
}
async function openSession() {
  await action(async current => {
    const scopes = administrator.value
      ? ['flow:read', 'flow:edit', 'flow:publish', 'flow:bind']
      : ['flow:read'];
    const result = await api.session(selected.value, scopes, abort.signal);
    if (current !== generation) return;
    session.value = result;
    await nextTick();
    const context = await api.editorContext(result.id, abort.signal);
    const prefix = `/api/v1/accounts/${Number(accountId.value)}/jrc_flow_delegation/sessions/${result.id}/flows`;
    const targets = await api.editorRequest(
      'get',
      prefix + '/targets',
      undefined,
      abort.signal
    );
    const module = await import(
      /* @vite-ignore */ `/jrc-flow-editor/editor.js?v=${nativeEditorBuild}`
    );
    if (current !== generation) return;
    unmountEditor?.();
    unmountEditor = module.mountNativeFlowEditor(editorElement.value, {
      accountId: Number(accountId.value),
      handleId: result.id,
      context,
      integrationIds: targets.data.map(target => target.integrationId),
      inboxNames: Object.fromEntries(
        inboxes.value.map(inbox => [inbox.id, inbox.name])
      ),
      request: api.editorRequest,
    });
  });
}
async function closeSession() {
  unmountEditor?.();
  unmountEditor = undefined;
  await action(async current => {
    await api.close(session.value.id, abort.signal);
    if (current === generation) session.value = null;
  });
}
async function claimInstallation() {
  await action(async current => {
    try {
      const result = await api.claimInstallation(
        installationGrant.value,
        installationTransfer.value,
        abort.signal
      );
      if (current === generation) {
        installation.value = result;
        notice.value = t('NATIVE.NOTICES.INSTALLATION_CLAIMED');
      }
    } finally {
      installationTransfer.value = '';
    }
  });
}
async function revoke() {
  await action(async current => {
    await api.revoke(registration.value.id, abort.signal);
    if (current === generation) {
      registration.value = null;
      session.value = null;
      notice.value = t('NATIVE.NOTICES.REVOKED');
    }
  });
}
watch(accountId, load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
  abort?.abort();
  unmountEditor?.();
  credential.value = '';
  transferNonce.value = '';
  installationTransfer.value = '';
});
</script>

<template>
  <main class="flex flex-col gap-5 overflow-auto p-6">
    <header class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-xl font-semibold">{{ t('NATIVE.TITLE') }}</h1>
        <p>{{ t('NATIVE.DESCRIPTION') }}</p>
      </div>
      <nav class="flex gap-4">
        <RouterLink :to="accountScopedRoute('jrc_flows')">
          {{ t('NATIVE.LOCAL_FLOWS') }}
        </RouterLink>
        <RouterLink :to="accountScopedRoute('jrc_broker_connections')">
          {{ t('NATIVE.CONNECTIONS') }}
        </RouterLink>
      </nav>
    </header>
    <p v-if="error" role="alert" class="text-n-ruby-11">{{ error }}</p>
    <p v-if="notice" role="status">{{ notice }}</p>
    <fieldset :disabled="busy || session" class="flex flex-col gap-2">
      <legend class="font-semibold">{{ t('NATIVE.INBOXES') }}</legend>
      <label
        v-for="inbox in inboxes"
        :key="inbox.id"
        class="flex items-center gap-2"
      >
        <input v-model="selected" type="checkbox" :value="inbox.id" />
        <span>{{ inbox.name }}</span>
      </label>
      <p v-if="!busy && !inboxes.length">{{ t('NATIVE.NO_INBOXES') }}</p>
    </fieldset>
    <section
      v-if="administrator"
      class="flex max-w-2xl flex-col gap-4 rounded border border-n-weak p-4"
    >
      <h2 class="font-semibold">{{ t('NATIVE.INSTALLATION') }}</h2>
      <p v-if="configuration?.configured">
        {{
          t('NATIVE.CREDENTIAL_VALID_UNTIL', {
            expiresAt: configuration.credentialExpiresAt,
          })
        }}
      </p>
      <form class="flex flex-col gap-2" @submit.prevent="configure">
        <label class="flex flex-col gap-1">
          <span>{{ t('NATIVE.BROKER_ADDRESS') }}</span>
          <input
            v-model="origin"
            type="url"
            required
            :disabled="busy"
            autocomplete="off"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span>{{ t('NATIVE.INITIAL_CREDENTIAL') }}</span>
          <input
            v-model="credential"
            type="password"
            required
            :disabled="busy"
            autocomplete="new-password"
          />
        </label>
        <button :disabled="busy || !credential">
          {{ t('NATIVE.VERIFY_CONNECTION') }}
        </button>
      </form>
      <form class="flex flex-col gap-2" @submit.prevent="register">
        <label class="flex flex-col gap-1">
          <span>{{ t('NATIVE.BROKER_CHALLENGE') }}</span>
          <input
            v-model="challenge"
            required
            :disabled="busy"
            autocomplete="off"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span>{{ t('NATIVE.TRANSFER_CODE') }}</span>
          <input
            v-model="transferNonce"
            type="password"
            required
            :disabled="busy"
            autocomplete="new-password"
          />
        </label>
        <button
          :disabled="busy || !selected.length || !configuration?.configured"
        >
          {{ t('NATIVE.CONFIRM_REGISTRATION') }}
        </button>
      </form>
      <button v-if="registration" :disabled="busy" @click="revoke">
        {{ t('NATIVE.REVOKE_REGISTRATION') }}
      </button>
      <form class="flex flex-col gap-2" @submit.prevent="claimInstallation">
        <label class="flex flex-col gap-1">
          <span>{{ t('NATIVE.INSTALLATION_AUTHORIZATION') }}</span>
          <input
            v-model="installationGrant"
            required
            :disabled="busy"
            autocomplete="off"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span>{{ t('NATIVE.INSTALLATION_TRANSFER_CODE') }}</span>
          <input
            v-model="installationTransfer"
            type="password"
            required
            :disabled="busy"
            autocomplete="new-password"
          />
        </label>
        <button :disabled="busy || !installationGrant || !installationTransfer">
          {{ t('NATIVE.AUTHORIZE_RENEWAL') }}
        </button>
      </form>
      <p v-if="installation">
        {{
          t('NATIVE.RENEWAL_VALID_UNTIL', { expiresAt: installation.expiresAt })
        }}
      </p>
    </section>
    <section class="flex flex-col items-start gap-2">
      <h2 class="font-semibold">{{ t('NATIVE.SESSION') }}</h2>
      <p v-if="session">
        {{ t('NATIVE.SESSION_VALID_UNTIL', { expiresAt: session.expiresAt }) }}
      </p>
      <button
        v-if="!session"
        :disabled="busy || !selected.length"
        @click="openSession"
      >
        {{ t('NATIVE.OPEN_SESSION') }}
      </button>
      <button v-else :disabled="busy" @click="closeSession">
        {{ t('NATIVE.CLOSE_SESSION') }}
      </button>
    </section>
    <div v-show="session" ref="editorElement" class="w-full" />
  </main>
</template>
