<script setup>
import ReportsView from '../../../serviceDesk/views/ReportsView.vue';
import ServiceDeskState from '../../../serviceDesk/components/ServiceDeskState.vue';
import { provideServiceDesk } from '../../../serviceDesk/composables/useServiceDesk';
import '../../../serviceDesk/serviceDesk.css';

const session = provideServiceDesk();
</script>

<template>
  <section class="jrc-service-desk-root !block !bg-transparent">
    <ReportsView
      v-if="
        session.state.status === 'ready' &&
        session.state.context?.capabilities?.reports?.index === true
      "
    />
    <ServiceDeskState
      v-else
      :status="
        session.state.status === 'ready' ? 'denied' : session.state.status
      "
      retry
      @retry="session.retry"
    />
  </section>
</template>
