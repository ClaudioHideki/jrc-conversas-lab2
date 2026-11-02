<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import LifecyclePolicyEditor from '../components/LifecyclePolicyEditor.vue';
import ServiceDeskState from '../components/ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';

const { t } = useI18n();
const session = useServiceDesk();
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.lifecycle_policies?.publish === true
);
</script>

<template>
  <section class="grid gap-4">
    <h2 class="text-xl font-semibold text-n-slate-12">
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.manage_policies') }}
    </h2>
    <LifecyclePolicyEditor v-if="allowed" />
    <ServiceDeskState v-else status="denied" />
  </section>
</template>
