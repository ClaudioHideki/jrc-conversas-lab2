<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LifecyclePolicyEditor from '../components/LifecyclePolicyEditor.vue';
import SupervisorPanel from '../components/SupervisorPanel.vue';
import TicketFilters from '../components/TicketFilters.vue';
import State from '../components/ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { useSupervisionReport } from '../composables/useSupervisionReport.js';
const { t } = useI18n();
const route = useRoute();
const session = useServiceDesk();
const filters = ref({ ...route.query });
const policyOpen = ref(false);
const { result, status, load } = useSupervisionReport(
  session,
  () => filters.value
);
const slaData = computed(() =>
  result.value?.supervision
    ? {
        ...result.value.supervision,
        by_agent: [],
        top_categories: [],
        evolution: [],
        capacity: [],
        tasks: null,
        approvals: null,
      }
    : null
);
</script>

<template>
  <section class="grid gap-4">
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">{{ t('JRC_SERVICE_DESK.SCREENS.sla') }}</h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.EXPERIENCE.help.sla') }}
        </p>
      </div>
    </header>
    <TicketFilters :query="filters" @apply="filters = $event" />
    <SupervisorPanel v-if="status === 'ready'" :data="slaData" compact />
    <State v-else :status="status" retry @retry="load" />
    <Button
      v-if="session.state.context?.capabilities?.lifecycle_policies?.index"
      variant="outline"
      :aria-expanded="policyOpen"
      :label="t('JRC_SERVICE_DESK.EXPERIENCE.manage_policies')"
      @click="policyOpen = !policyOpen"
    />
    <LifecyclePolicyEditor
      v-if="
        policyOpen &&
        session.state.context?.capabilities?.lifecycle_policies?.index
      "
    />
  </section>
</template>
