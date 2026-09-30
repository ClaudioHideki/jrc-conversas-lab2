<script setup>
import { computed } from 'vue';
import { useCommercialLabels } from '../../composables/useCommercialLabels';
import CrmBadge from './CrmBadge.vue';

const props = defineProps({
  value: {
    type: String,
    required: true,
  },
});

const { statusLabel } = useCommercialLabels();

const mappedColor = computed(() => {
  const statusColors = {
    open: 'blue',
    won: 'green',
    lost: 'red',
    cancelled: 'gray',
    new: 'blue',
    in_contact: 'yellow',
    qualified: 'purple',
    converted: 'green',
    discarded: 'red',
    unqualified: 'red',
    draft: 'gray',
    pending_approval: 'yellow',
    sent: 'purple',
    viewed: 'blue',
    accepted: 'green',
    rejected: 'red',
    canceled: 'gray',
    scheduled: 'blue',
    in_progress: 'yellow',
    completed: 'green',
    overdue: 'red',
  };
  return statusColors[props.value?.toLowerCase()] || 'gray';
});

const mappedLabel = computed(() => statusLabel(props.value));
</script>

<template>
  <CrmBadge :color="mappedColor">
    {{ mappedLabel }}
  </CrmBadge>
</template>
