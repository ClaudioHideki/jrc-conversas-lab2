<script setup>
import MasterContactDetails from './MasterContactDetails.vue';
import { useCustomerMaster } from '../useCustomerMaster';
const props = defineProps({
  contactId: { type: [Number, String], default: null },
  expandedByDefault: { type: Boolean, default: false },
});
const emit = defineEmits(['updated', 'denied']);
const { accountId, enabled } = useCustomerMaster();
</script>

<template>
  <MasterContactDetails
    :key="`${accountId}:${props.contactId}:${enabled}`"
    :contact-id="props.contactId"
    :expanded-by-default="props.expandedByDefault"
    @updated="emit('updated')"
    @denied="emit('denied')"
  />
</template>
