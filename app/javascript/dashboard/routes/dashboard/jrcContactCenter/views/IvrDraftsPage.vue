<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import IvrDraftWorkspace from '../components/IvrDraftWorkspace.vue';

const route = useRoute();
const user = useMapGetter('getCurrentUser');
const contextKey = computed(() => {
  const account = user.value?.accounts?.find(
    row => String(row.id) === String(route.params.accountId)
  );
  return JSON.stringify([
    route.params.accountId,
    user.value?.id,
    user.value?.type,
    account?.role,
    account?.custom_role_id,
    account?.contact_center_eligible,
    account?.permissions?.slice().sort(),
  ]);
});
</script>

<template>
  <IvrDraftWorkspace
    v-if="user?.id"
    :key="contextKey"
    :account-id="route.params.accountId"
  />
</template>
