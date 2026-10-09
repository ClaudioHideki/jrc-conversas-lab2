<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Panel from '../components/ServiceDeskPanel.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { useServiceDeskStructure } from 'dashboard/composables/useServiceDeskStructure';
import { canPreviewScreen } from '../helpers/access';
import { SERVICE_DESK_ROUTES, serviceDeskRouteName } from '../routeDefinitions';
const { t } = useI18n();
const router = useRouter();
const session = useServiceDesk();
const structure = useServiceDeskStructure(
  session.accountId,
  session.userId,
  session.enabled
);
const sections = [
  { key: 'statuses', icon: 'i-lucide-list-checks' },
  { key: 'priorities', icon: 'i-lucide-flag' },
  { key: 'categories', icon: 'i-lucide-tags' },
  { key: 'ticket_types', icon: 'i-lucide-list-filter' },
  { key: 'queues', icon: 'i-lucide-network' },
  { key: 'units', icon: 'i-lucide-building' },
  { key: 'operator_companies', icon: 'i-lucide-building-2' },
  { key: 'assignees', icon: 'i-lucide-users' },
  { key: 'catalog', icon: 'i-lucide-book-open-check' },
  { key: 'sla', icon: 'i-lucide-clock' },
  { key: 'automations', icon: 'i-lucide-workflow' },
];
const visibleSections = computed(() =>
  sections.filter(section =>
    canPreviewScreen(
      session.state.context,
      SERVICE_DESK_ROUTES.find(item => item.key === section.key)
    )
  )
);
const open = key =>
  router.push({
    name: serviceDeskRouteName(key),
    params: { accountId: session.accountId.value },
  });
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
        v-for="resource in ['operator_companies', 'units'].filter(
          key => structure.state.context?.capabilities?.[key]
        )"
        :key="`structure:${resource}`"
        :title="t(`JRC_SERVICE_DESK.SCREENS.${resource}`)"
        icon="i-lucide-building-2"
      >
        <p class="text-sm text-n-slate-11 mb-3">
          {{ t('JRC_SERVICE_DESK.EXPERIENCE.structure_authority') }}
        </p>
        <Button
          variant="outline"
          :label="t('JRC_SERVICE_DESK.COMMON.open')"
          @click="
            router.push({
              name: 'jrc_service_desk_structure',
              params: { accountId: session.accountId.value },
              query: { resource },
            })
          "
        />
      </Panel>
      <Panel
        v-if="structure.state.context?.capabilities?.unit_memberships"
        :title="t('JRC_SERVICE_DESK.UNIT_ACCESS.title')"
        icon="i-lucide-user-round-check"
      >
        <p class="text-xs text-n-slate-11 mb-4">
          {{ t('JRC_SERVICE_DESK.UNIT_ACCESS.help') }}
        </p>
        <Button
          :label="t('JRC_SERVICE_DESK.UNIT_ACCESS.title')"
          @click="
            router.push({
              name: 'jrc_service_desk_structure',
              params: { accountId: session.accountId.value },
              query: { resource: 'unit_memberships' },
            })
          "
        />
      </Panel>
      <Panel
        v-for="section in visibleSections"
        :key="section.key"
        :title="t(`JRC_SERVICE_DESK.SCREENS.${section.key}`)"
        :icon="section.icon"
      >
        <p class="text-xs text-n-slate-11 mb-4">
          {{ t(`JRC_SERVICE_DESK.EXPERIENCE.help.${section.key}`) }}
        </p>
        <Button
          size="sm"
          variant="outline"
          color="slate"
          :label="t('JRC_SERVICE_DESK.COMMON.open')"
          @click="open(section.key)"
        />
      </Panel>
    </div>
    <div
      class="mt-4 rounded-xl border border-n-weak bg-n-solid-1 p-4 text-sm text-n-slate-11"
    >
      {{ t('JRC_SERVICE_DESK.EXPERIENCE.settings_hint') }}
    </div>
  </section>
</template>
