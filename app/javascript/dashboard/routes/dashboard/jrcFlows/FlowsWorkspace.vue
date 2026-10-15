<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import FlowsPage from './FlowsPage.vue';
import AgentFlowsPage from './AgentFlowsPage.vue';
import messages from './workspace.en.json';

const { t } = useI18n({
  useScope: 'local',
  messages: { en: messages, pt_BR: messages, pt: messages },
});
const store = useStore();
const { currentAccount, accountId, accountScopedRoute } = useAccount();
const enabled = computed(
  () =>
    window.chatwootConfig?.jrcFlowsEnabled === true &&
    currentAccount.value?.features?.jrc_flows === true
);
const brokerEnabled = computed(
  () =>
    window.chatwootConfig?.jrcBrokerEnabled === true &&
    currentAccount.value?.features?.jrc_broker === true
);
const administrator = computed(
  () =>
    store.getters.getCurrentRole === 'administrator' &&
    !store.getters.getCurrentCustomRoleId
);
</script>

<template>
  <div class="flex h-full min-w-0 flex-1 flex-col overflow-hidden">
    <div
      v-if="brokerEnabled"
      class="flex justify-end border-b border-n-weak bg-n-solid-2 px-6 py-2"
    >
      <RouterLink
        class="flex items-center gap-2 text-sm text-n-blue-11"
        :to="accountScopedRoute('jrc_broker_connections')"
      >
        <span class="i-ri-whatsapp-line size-4" />
        {{ t('CONNECTIONS') }}
      </RouterLink>
    </div>
    <RouterLink
      v-if="enabled"
      class="px-6 py-2 text-n-blue-11"
      :to="accountScopedRoute('jrc_flows_native')"
    >
      {{ t('BROKER_FLOW') }}
    </RouterLink>
    <p v-if="!enabled" class="p-6 text-n-slate-11">{{ t('DISABLED') }}</p>
    <FlowsPage v-else-if="administrator" :key="accountId" />
    <AgentFlowsPage v-else :key="accountId" />
  </div>
</template>
