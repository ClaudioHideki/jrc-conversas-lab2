<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
const props = defineProps({ page: { type: Object, required: true } });
const route = useRoute();
const accountKey = computed(() => String(route.params.accountId));
</script>

<template>
  <component
    :is="props.page"
    :key="accountKey"
  />
</template>
