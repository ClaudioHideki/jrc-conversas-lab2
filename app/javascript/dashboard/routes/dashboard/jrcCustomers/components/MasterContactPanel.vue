<script setup>
import MasterContactDetails from './MasterContactDetails.vue';
import { useCustomerMaster } from '../useCustomerMaster';
const props = defineProps({
  contactId: { type: [Number, String], default: null },
});
const emit = defineEmits(['updated']);
const { accountId, enabled } = useCustomerMaster();
</script>

<template>
  <MasterContactDetails
    :key="`${accountId}:${props.contactId}:${enabled}`"
    :contact-id="props.contactId"
    @updated="emit('updated')"
  />
</template>
