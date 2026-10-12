<script setup>
import { defineAsyncComponent } from 'vue';
const props = defineProps({ kind: { type: String, required: true } });
const emit = defineEmits(['close']);
const LeadCreateModal = defineAsyncComponent(
  () => import('dashboard/routes/dashboard/crm/views/leads/LeadCreateModal.vue')
);
const DealsIndex = defineAsyncComponent(
  () => import('dashboard/routes/dashboard/crm/views/deals/DealsIndex.vue')
);
</script>

<template>
  <LeadCreateModal
    v-if="props.kind === 'LEAD'"
    @close="emit('close')"
    @created="emit('close')"
  />
  <DealsIndex v-else creation-only @close="emit('close')" />
</template>
