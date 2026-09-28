<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LifecyclePolicyEditor from '../components/LifecyclePolicyEditor.vue';
import ConfigurationManager from '../components/ConfigurationManager.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import PendingAction from '../components/PendingAction.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canPreviewScreen } from '../helpers/access';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions';
const { t } = useI18n();
const router = useRouter();
const session = useServiceDesk();
const sections = [
  { key: 'statuses', icon: 'i-lucide-list-checks' }, { key: 'priorities', icon: 'i-lucide-flag' },
  { key: 'categories', icon: 'i-lucide-tags' }, { key: 'queues', icon: 'i-lucide-network' },
  { key: 'units', icon: 'i-lucide-building' }, { key: 'operator_companies', icon: 'i-lucide-building-2' },
  { key: 'assignees', icon: 'i-lucide-users' }, { key: 'sla', icon: 'i-lucide-clock' },
  { key: 'automations', icon: 'i-lucide-workflow' },
];
const visibleSections = computed(() => sections.filter(section => canPreviewScreen(session.state.context, SERVICE_DESK_ROUTES.find(item => item.key === section.key))));
const open = key => router.push({ name: serviceDeskRouteName(key), params: { accountId: session.accountId.value } });
</script>
<template>
  <section>
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t('JRC_SERVICE_DESK.SCREENS.settings') }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.CATALOG.settings_help') }}
        </p>
      </div>
    </header>
    <div class="sd-settings-grid">
      <Panel
        v-for="section in visibleSections"
        :key="section.key"
        :title="t(`JRC_SERVICE_DESK.SCREENS.${section.key}`)"
        :icon="section.icon"
      >
        <p class="text-xs text-n-slate-11 mb-4">
          {{ t('JRC_SERVICE_DESK.CATALOG.form_notice') }}
        </p>
        <Button
          size="sm"
          variant="outline"
          color="slate"
          :label="t('JRC_SERVICE_DESK.COMMON.fields_preview')"
          @click="open(section.key)"
        />
      </Panel>
    </div>
    <ConfigurationManager resource="services" />
    <LifecyclePolicyEditor />
    <Panel class="mt-4" :title="t('JRC_SERVICE_DESK.PLANNED.portal')">
      <p class="text-sm text-n-slate-11">
        {{ t('JRC_SERVICE_DESK.PLANNED.portal_help') }}
      </p>
      <PendingAction :label="t('JRC_SERVICE_DESK.COMMON.configure')" />
    </Panel>
  </section>
</template>
