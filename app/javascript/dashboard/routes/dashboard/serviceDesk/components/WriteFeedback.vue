<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
const props = defineProps({ status: { type: String, default: 'idle' } });
const { t } = useI18n();
const color = computed(() => props.status === 'confirmed' ? 'teal' : props.status === 'saving' ? 'blue' : 'amber');
</script>
<template>
  <Banner v-if="status !== 'idle'" :color="color" role="status" aria-live="polite" class="my-3">
    {{ t(`JRC_SERVICE_DESK.OPS.STATUS.${status}`) }}
  </Banner>
</template>
