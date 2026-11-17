<script setup>
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ConfigurationAuditPanel from './ConfigurationAuditPanel.vue';
import AdministrationSection from './AdministrationSection.vue';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  context: { type: Object, required: true },
});
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const source = computed(
  () =>
    route.query.audit_source ||
    (props.context.capabilities.configuration_audit
      ? 'configuration'
      : 'provider')
);
const tabs = [
  {
    key: 'configuration',
    label: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.CONFIGURATIONS'),
  },
  {
    key: 'provider',
    label: t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.PROVIDER_EVENTS'),
  },
];
const select = key =>
  router.replace({ query: { ...route.query, audit_source: key } });
</script>

<template>
  <div class="min-w-0 space-y-4" data-configuration-audit-page>
    <nav
      class="flex flex-wrap gap-2"
      :aria-label="t('JRC_CONTACT_CENTER.ADMIN.AUDIT')"
    >
      <button
        v-for="tab in tabs"
        :key="tab.key"
        type="button"
        class="rounded-lg border border-n-blue-6 px-4 py-2 text-sm"
        :class="
          source === tab.key
            ? 'bg-n-blue-9 text-white'
            : 'bg-n-blue-2 text-n-blue-11'
        "
        :aria-pressed="source === tab.key"
        @click="select(tab.key)"
      >
        {{ tab.label }}
      </button>
    </nav>
    <ConfigurationAuditPanel
      v-if="
        source === 'configuration' && context.capabilities.configuration_audit
      "
      :key="String(accountId)"
      :account-id="accountId"
      :context="context"
    />
    <p
      v-else-if="source === 'configuration'"
      role="status"
      class="rounded-xl border border-n-amber-6 p-4 text-sm text-n-amber-11"
    >
      {{ t('JRC_CONTACT_CENTER.CONFIGURATION_AUDIT.NOT_ENABLED') }}
    </p>
    <AdministrationSection
      v-else-if="source === 'provider'"
      :account-id="accountId"
      :card="{ key: 'audit', state: 'read_only' }"
      :context="context"
    />
    <p v-else role="alert" class="text-sm text-n-ruby-11">
      {{ t('JRC_CONTACT_CENTER.ADMIN.DENIED') }}
    </p>
  </div>
</template>
