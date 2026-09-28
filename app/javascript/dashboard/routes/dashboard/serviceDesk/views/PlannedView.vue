<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import State from '../components/ServiceDeskState.vue';
import PendingAction from '../components/PendingAction.vue';
import KpiCard from '../components/KpiCard.vue';
import { PLANNED_SCREENS } from '../helpers/presentation';
const props = defineProps({ screen: { type: String, required: true } });
const { t } = useI18n();
const activeTab = ref(0);
const definition = computed(() => PLANNED_SCREENS[props.screen]);
const tabs = computed(() => ['list', 'rules', 'history'].map((value, index) => ({ value, index, label: t(`JRC_SERVICE_DESK.PLANNED.${value}`) })));
const specialHelp = computed(() => ({ contracts: 'contract_help', knowledge: 'knowledge_help' })[props.screen] || 'data_notice');
</script>
<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t(`JRC_SERVICE_DESK.SCREENS.${screen}`) }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.PLANNED.subtitle') }}
        </p>
      </div>
      <div class="flex gap-3 flex-wrap">
        <PendingAction
          v-for="action in definition.actions"
          :key="action"
          :label="t(`JRC_SERVICE_DESK.PLANNED.${action}`)"
        />
        <PendingAction v-if="screen === 'reports'" :label="t('JRC_SERVICE_DESK.COMMON.export')" />
      </div>
    </header>
    <p class="text-sm text-n-slate-11">
      {{ t(`JRC_SERVICE_DESK.PLANNED.${specialHelp}`) }}
    </p>
    <div class="overflow-x-auto mb-4">
      <TabBar :tabs="tabs" :initial-active-tab="activeTab" @tab-changed="activeTab = $event.index" />
    </div>
    <div v-if="['reports', 'surveys', 'sla'].includes(screen)" class="sd-kpi-grid">
      <KpiCard
        v-for="field in definition.sections"
        :key="field"
        :label="t(`JRC_SERVICE_DESK.FIELDS.${field}`)"
        icon="i-lucide-chart-no-axes-combined"
      />
    </div>
    <div class="sd-filter-card">
      <div class="sd-fields-grid">
        <Input
          :label="t('JRC_SERVICE_DESK.COMMON.search')"
          :placeholder="t('JRC_SERVICE_DESK.COMMON.pending_cp4')"
          disabled
        />
        <Input
          :label="t('JRC_SERVICE_DESK.SCOPE.unit')"
          :placeholder="t('JRC_SERVICE_DESK.COMMON.pending_cp4')"
          disabled
        />
      </div>
    </div>
    <div class="sd-two-columns">
      <Panel :title="tabs[activeTab].label">
        <div class="sd-column-hints">
          <span v-for="field in definition.columns" :key="field">
            {{ t(`JRC_SERVICE_DESK.FIELDS.${field}`) }}
          </span>
        </div>
        <State status="pending" :description="t('JRC_SERVICE_DESK.PLANNED.data_notice')" />
      </Panel>
      <div class="grid gap-4">
        <Panel v-for="field in definition.sections" :key="field" :title="t(`JRC_SERVICE_DESK.FIELDS.${field}`)">
          <State status="pending" compact />
        </Panel>
      </div>
    </div>
  </section>
</template>
