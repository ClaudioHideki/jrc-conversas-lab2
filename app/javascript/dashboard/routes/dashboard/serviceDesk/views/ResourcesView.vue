<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ScopeBar from '../components/ScopeBar.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import NativeResourcesPanel from '../components/NativeResourcesPanel.vue';
defineProps({ screen: { type: String, required: true } });
const { t } = useI18n();
const unitId = ref('');
const operatorId = ref('');
const resources = ref(null);
const canExport = computed(() => resources.value?.canExport === true);
defineExpose({ canExport, exportCsv: () => resources.value?.exportCsv() });
</script>

<template>
  <section class="grid gap-5">
    <header class="flex items-center gap-3">
      <span
        aria-hidden="true"
        class="grid size-12 shrink-0 place-items-center rounded-xl bg-blue-100 text-blue-700"
        ><span class="i-lucide-box size-7"
      /></span>
      <div>
        <h2 class="m-0 text-2xl font-bold">
          {{ t(`JRC_SERVICE_DESK.SCREENS.${screen}`) }}
        </h2>
        <p v-if="screen === 'assets'" class="mb-0 mt-1 text-sm text-n-slate-11">
          {{ t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.assets_help') }}
        </p>
      </div>
    </header>
    <Panel
      :title="t('JRC_SERVICE_DESK.REPORT_EXPERIENCE.filters')"
      icon="i-lucide-list-filter"
    >
      <ScopeBar v-model:unit-id="unitId" v-model:operator-id="operatorId" />
    </Panel>
    <NativeResourcesPanel
      ref="resources"
      :unit-id="unitId"
      :kind="screen === 'assets' ? 'asset' : 'change'"
    />
  </section>
</template>
