<script setup>
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualShowcasePage from '../../components/visual/VisualShowcasePage.vue';
import { contactCenterScreen } from '../../demo/contactCenterVisualCatalog';
import CallWorkspace from '../CallWorkspace.vue';

const { t } = useI18n();

const route = useRoute();
const context = ref(null);
const failed = ref(false);
const accountId = computed(() => route.params.accountId);
const callId = computed(() =>
  Number(route.params.callId || route.query.callId)
);
const hasCall = computed(
  () => Number.isInteger(callId.value) && callId.value > 0
);

let generation = 0;
watch(
  accountId,
  async id => {
    generation += 1;
    const version = generation;
    context.value = null;
    failed.value = false;
    try {
      const { data } = await JrcContactCenterAPI.context(id);
      if (version === generation) context.value = data;
    } catch {
      if (version === generation) failed.value = true;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div>
    <VisualShowcasePage :screen="contactCenterScreen('call', t)" />
    <section v-if="hasCall" class="px-4 pb-6 sm:px-6">
      <CallWorkspace
        :key="`${accountId}-${callId}`"
        :account-id="accountId"
        :call-id="callId"
        :context="context"
      />
    </section>
    <p v-else-if="failed" class="sr-only">
      {{ $t('JRC_CONTACT_CENTER.VISUAL.CONTEXTO_OPERACIONAL_INDISPONIVEL') }}
    </p>
  </div>
</template>
