<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Banner from 'dashboard/components-next/banner/Banner.vue';
const props = defineProps({ status: { type: String, default: 'idle' } });
const { t } = useI18n();
const color = computed(() => {
  if (props.status === 'confirmed') return 'teal';
  if (props.status === 'saving') return 'blue';
  return 'amber';
});
</script>

<template>
  <Banner
    v-if="status !== 'idle'"
    :color="color"
    role="status"
    aria-live="polite"
    class="my-3"
  >
    {{
      status === 'forbidden'
        ? t('JRC_SERVICE_DESK.LIFECYCLE.feedback.denied')
        : t(`JRC_SERVICE_DESK.OPS.STATUS.${status}`)
    }}
  </Banner>
</template>
