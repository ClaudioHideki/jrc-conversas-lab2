<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import LifecyclePolicyEditor from '../components/LifecyclePolicyEditor.vue';
import NotificationPolicyEditor from '../components/NotificationPolicyEditor.vue';
import ConfigurationManager from '../components/ConfigurationManager.vue';
import OperationalRulePanel from '../components/OperationalRulePanel.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
const { t } = useI18n();
const session = useServiceDesk();
const selected = ref('lifecycle');
const sections = computed(() => {
  if (
    session.state.status !== 'ready' ||
    session.state.context?.capabilities?.automations?.index !== true
  )
    return [];
  const capabilities = session.state.context.capabilities;
  return [
    {
      key: 'lifecycle',
      allowed: capabilities.lifecycle_policies?.publish === true,
    },
    { key: 'ola', allowed: capabilities.configuration?.queues === true },
    {
      key: 'operational',
      allowed: Object.values(capabilities.operational_rules || {}).some(
        value => value === true
      ),
    },
    {
      key: 'notifications',
      allowed: capabilities.notifications?.manage === true,
    },
  ].filter(row => row.allowed);
});
const active = computed(
  () =>
    sections.value.find(row => row.key === selected.value)?.key ||
    sections.value[0]?.key
);
</script>

<template>
  <section v-if="sections.length">
    <header class="sd-page-heading">
      <div>
        <h2 class="sd-page-title">
          {{ t('JRC_SERVICE_DESK.SCREENS.automations') }}
        </h2>
        <p class="sd-page-subtitle">
          {{ t('JRC_SERVICE_DESK.CLOCK_AUTOMATION.automations_help') }}
        </p>
      </div>
    </header>
    <nav
      class="flex flex-wrap gap-2"
      :aria-label="t('JRC_SERVICE_DESK.SCREENS.automations')"
    >
      <Button
        v-for="row in sections"
        :key="row.key"
        size="sm"
        :variant="active === row.key ? 'solid' : 'outline'"
        :label="t(`JRC_SERVICE_DESK.CLOCK_AUTOMATION.sections.${row.key}`)"
        @click="selected = row.key"
      />
    </nav>
    <LifecyclePolicyEditor v-if="active === 'lifecycle'" />
    <ConfigurationManager v-else-if="active === 'ola'" resource="queues" />
    <NotificationPolicyEditor v-else-if="active === 'notifications'" />
    <OperationalRulePanel v-else-if="active === 'operational'" />
  </section>
</template>
