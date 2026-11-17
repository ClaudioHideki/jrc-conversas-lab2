<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import SipSettingsPage from './SipSettingsPage.vue';

const route = useRoute();
const user = useMapGetter('getCurrentUser');
const contextKey = computed(
  () => `${route.params.accountId}:${user.value.id}:${user.value.type}`
);
</script>

<template>
  <SipSettingsPage :key="contextKey" />
</template>
