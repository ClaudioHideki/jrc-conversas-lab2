<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ScopeBar from '../components/ScopeBar.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import NativeResourcesPanel from '../components/NativeResourcesPanel.vue';
defineProps({ screen: { type: String, required: true } });
const { t } = useI18n();
const unitId = ref('');
const operatorId = ref('');
</script>

<template>
  <Panel :title="t(`JRC_SERVICE_DESK.SCREENS.${screen}`)">
    <ScopeBar v-model:unit-id="unitId" v-model:operator-id="operatorId" />
    <NativeResourcesPanel
      :unit-id="unitId"
      :kind="screen === 'assets' ? 'asset' : 'change'"
    />
  </Panel>
</template>
