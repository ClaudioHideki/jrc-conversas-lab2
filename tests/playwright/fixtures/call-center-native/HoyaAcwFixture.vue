<script setup>
// Test boundary only: actual workspace, scoped Rails responses and no SIP initialization.
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';
import HoyaInboxWorkspace from 'dashboard/routes/dashboard/inbox/HoyaInboxWorkspace.vue';

const route = useRoute();
const { t } = useI18n();
const accountId = computed(() => Number(route.params.accountId));
const callId = computed(() => Number(route.params.callId));
const context = ref(null);
const calls = ref([]);
const failed = ref(false);
const loading = ref(true);
const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const [scope, record] = await Promise.all([
      API.context(accountId.value),
      API.call(accountId.value, callId.value),
    ]);
    context.value = scope.data;
    calls.value = [record.data.item];
  } catch {
    context.value = null;
    calls.value = [];
    failed.value = true;
  } finally {
    loading.value = false;
  }
};
onMounted(load);
</script>

<template>
  <section
    class="h-[calc(100dvh-3rem)] min-h-0 w-full min-w-0"
    data-native-hoya-acw
  >
    <p v-if="failed" role="alert">{{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}</p>
    <p v-else-if="loading" role="status">
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </p>
    <HoyaInboxWorkspace
      v-else
      :account-id="accountId"
      :current-call-id="callId"
      :calls="calls"
      :context="context"
      :inbox-for="() => null"
      :softphone-access="false"
      channel-filter="voice"
      status-filter="all"
      @refresh="load"
    />
  </section>
</template>
