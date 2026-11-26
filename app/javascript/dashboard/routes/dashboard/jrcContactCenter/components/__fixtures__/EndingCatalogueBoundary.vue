<script setup>
// Unit validation readiness only. Real catalogue acceptance requires native CI.
import { onMounted } from 'vue';
const emit = defineEmits(['ready']);
onMounted(() => emit('ready', true));
</script>

<template>
  <div data-native-catalogue />
</template>
