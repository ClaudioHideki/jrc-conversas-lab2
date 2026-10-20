<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';
import Button from 'dashboard/components-next/button/Button.vue';
import ConnectionPanel from 'dashboard/components-next/jrc-broker/ConnectionPanel.vue';
import HumanAssignmentPolicy from 'dashboard/components-next/jrc-broker/HumanAssignmentPolicy.vue';

const { t } = useI18n();
const { accountId, currentAccount } = useAccount();
const store = useStore();
const { isAdmin } = useAdmin();
const inboxes = ref([]);
const selectedId = ref(null);
const loading = ref(false);
const error = ref('');
const loggedOut = ref(false);
const enabled = computed(
  () =>
    !loggedOut.value &&
    window.chatwootConfig?.jrcBrokerEnabled === true &&
    currentAccount.value?.features?.jrc_broker === true
);
const selectedInbox = computed(() =>
  inboxes.value.find(inbox => inbox.id === selectedId.value)
);
let controller;
let generation = 0;
const clear = () => {
  generation += 1;
  controller?.abort();
  inboxes.value = [];
  selectedId.value = null;
  loading.value = false;
  error.value = '';
};
const load = async () => {
  clear();
  if (!enabled.value) return;
  const current = generation;
  controller = new AbortController();
  loading.value = true;
  try {
    const result = await createJrcBrokerApi(accountId.value).inboxes(
      controller.signal
    );
    if (current !== generation) return;
    inboxes.value = result.filter(inbox => inbox.jrc_broker_bound === true);
    selectedId.value = inboxes.value[0]?.id ?? null;
  } catch (failure) {
    if (current !== generation) return;
    error.value = [401, 403, 404].includes(failure?.response?.status)
      ? 'DENIED'
      : 'UNAVAILABLE';
  } finally {
    if (current === generation) loading.value = false;
  }
};
watch(() => [accountId.value, enabled.value], load, {
  immediate: true,
  flush: 'sync',
});
const unsubscribe = store.subscribe(mutation => {
  if (mutation.type === 'LOGOUT') loggedOut.value = true;
});
onBeforeUnmount(() => {
  clear();
  unsubscribe();
});
</script>

<template>
  <main class="flex-1 overflow-y-auto bg-n-background p-6">
    <div class="mx-auto flex w-full max-w-4xl flex-col gap-5">
      <header class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold text-n-slate-12">
            {{ t('JRC_BROKER.CONNECT_WHATSAPP') }}
          </h1>
          <p class="mt-2 text-sm text-n-slate-11">
            {{ t('JRC_BROKER.CONNECTIONS_HELP') }}
          </p>
        </div>
        <Button
          v-if="enabled"
          data-testid="refresh-connections"
          variant="outline"
          icon="i-lucide-refresh-cw"
          :label="t('JRC_BROKER.REFRESH_CONNECTIONS')"
          :disabled="loading"
          @click="load"
        />
      </header>
      <p v-if="!enabled" role="status">{{ t('JRC_BROKER.DISABLED') }}</p>
      <p v-else-if="loading" role="status">
        {{ t('JRC_BROKER.LOADING_CONNECTIONS') }}
      </p>
      <p v-else-if="error" role="alert">
        {{ t(`JRC_BROKER.ERROR.${error}`) }}
      </p>
      <p v-else-if="!inboxes.length" data-testid="no-connections" role="status">
        {{ t('JRC_BROKER.NO_CONNECTIONS') }}
      </p>
      <template v-else>
        <label class="flex flex-col gap-2 text-sm text-n-slate-12">
          <span>{{ t('JRC_BROKER.SELECT_INBOX') }}</span>
          <select v-model.number="selectedId" class="w-full">
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </label>
        <p class="text-sm text-n-slate-11">
          {{ t('JRC_BROKER.AGENT_CONNECTIONS_HELP') }}
        </p>
        <ConnectionPanel
          v-if="selectedInbox"
          :key="`${accountId}:${selectedInbox.id}`"
          :account-id="accountId"
          :inbox-id="selectedInbox.id"
        />
      </template>
      <HumanAssignmentPolicy
        v-if="enabled && isAdmin"
        :key="accountId"
        :account-id="accountId"
      />
    </div>
  </main>
</template>
