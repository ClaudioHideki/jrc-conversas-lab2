<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import State from '../components/ServiceDeskState.vue';
const route = useRoute(); const router = useRouter(); const { t } = useI18n();
const status = computed(() => ['denied', 'unauthenticated', 'error'].includes(route.query.reason) ? route.query.reason : 'denied');
</script>
<template>
  <section class="flex-1 p-6">
    <h1 class="text-xl font-semibold">{{ t('JRC_SERVICE_DESK.MODULE') }}</h1>
    <State :status="status" />
    <Button variant="outline" color="slate" :label="t('JRC_SERVICE_DESK.NATIVE.back_to_jrc')" @click="router.push({ name: 'home', params: { accountId: route.params.accountId } })" />
  </section>
</template>
