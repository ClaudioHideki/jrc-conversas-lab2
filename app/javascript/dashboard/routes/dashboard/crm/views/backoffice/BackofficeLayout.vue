<script setup>
import { computed, watch, ref, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { backofficeRequirementsAPI } from 'dashboard/api/crm/backofficeRequirements';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { useRoute, useRouter } from 'vue-router';
import ModuleTabs from 'dashboard/components-next/navigation/ModuleTabs.vue';
import ModuleSegmentFilter from 'dashboard/routes/dashboard/jrcCustomers/components/ModuleSegmentFilter.vue';
import { crmControlClasses } from '../../crmControlClasses';
import BackofficeOverview from './BackofficeOverview.vue';
import BackofficeWorklist from './BackofficeWorklist.vue';
import BackofficeRequest360 from './BackofficeRequest360.vue';
import BackofficeNewRequest from './BackofficeNewRequest.vue';
import SignatureSettings from './SignatureSettings.vue';
import BackofficeRequirementSettings from './BackofficeRequirementSettings.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

const store = useStore();
const canManageRequirements = ref(false);
let capabilityGeneration = 0;
let capabilityAbort;
watch(
  () => authorityScope(store.getters),
  async identity => {
    capabilityGeneration += 1;
    const generation = capabilityGeneration;
    capabilityAbort?.abort();
    capabilityAbort = new AbortController();
    canManageRequirements.value = false;
    const account = store.getters.getCurrentAccountId;
    if (!account) return;
    try {
      const { data } = await backofficeRequirementsAPI.capabilities(account, {
        signal: capabilityAbort.signal,
      });
      if (
        generation === capabilityGeneration &&
        identity === authorityScope(store.getters)
      )
        canManageRequirements.value = data?.can_manage === true;
    } catch {
      if (generation === capabilityGeneration)
        canManageRequirements.value = false;
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  capabilityGeneration += 1;
  capabilityAbort?.abort();
});
const route = useRoute();
const router = useRouter();
const { text } = useBackofficePresentation();
const primaryKeys = [
  'overview',
  'requests',
  'docs',
  'approvals',
  'contracts',
  'reports',
];
const groups = [
  {
    key: 'OPERATION',
    tone: 'cyan',
    icon: 'i-lucide-workflow',
    sections: ['process', 'implement', 'provision', 'finance'],
  },
  {
    key: 'CONTROL',
    tone: 'violet',
    icon: 'i-lucide-settings',
    sections: ['mine', 'issues', 'changes', 'sla', 'signature', 'requirements'],
  },
];
const sections = [...primaryKeys, ...groups.flatMap(group => group.sections)];
const tones = {
  overview: 'blue',
  requests: 'teal',
  docs: 'amber',
  approvals: 'violet',
  contracts: 'cyan',
  reports: 'rose',
  mine: 'teal',
  issues: 'rose',
  changes: 'amber',
  sla: 'violet',
  process: 'blue',
  implement: 'teal',
  provision: 'violet',
  finance: 'amber',
  signature: 'violet',
  requirements: 'amber',
};
const icons = {
  overview: 'i-lucide-layout-dashboard',
  requests: 'i-lucide-inbox',
  docs: 'i-lucide-files',
  approvals: 'i-lucide-check-check',
  contracts: 'i-lucide-file-signature',
  reports: 'i-lucide-chart-column',
  mine: 'i-lucide-list-checks',
  issues: 'i-lucide-triangle-alert',
  changes: 'i-lucide-git-compare',
  sla: 'i-lucide-clock',
  process: 'i-lucide-shopping-cart',
  implement: 'i-lucide-list-checks',
  provision: 'i-lucide-server',
  finance: 'i-lucide-wallet',
  signature: 'i-lucide-file-signature',
  requirements: 'i-lucide-list-checks',
};
const entry = key => ({
  key,
  label: text(`NAV.${key}`),
  tone: tones[key],
  icon: icons[key],
  to: {
    name: 'crm_backoffice',
    params: { section: key },
    query: { customer_segment_id: route.query.customer_segment_id },
  },
});
const primary = computed(() => primaryKeys.map(entry));
const navigationGroups = computed(() =>
  groups.map(group => ({
    ...group,
    label: text(group.key),
    entries: group.sections
      .filter(key => key !== 'requirements' || canManageRequirements.value)
      .map(entry),
  }))
);
const section = computed(() => {
  const key =
    route.params.section === 'queues' ? 'requests' : route.params.section;
  return sections.includes(key) ? key : 'overview';
});
const tabBySection = {
  docs: 'documents',
  implement: 'checklist',
  provision: 'checklist',
  issues: 'issues',
  finance: 'finance',
  approvals: 'operations',
};
// Preserve saved links from the former workspace without reopening a long embedded editor.
watch(
  () => route.fullPath,
  () => {
    if (route.query.requestId) {
      router.replace({
        name: 'crm_backoffice_request',
        params: {
          accountId: route.params.accountId,
          requestId: route.query.requestId,
        },
        query: { tab: tabBySection[route.params.section] || 'operations' },
      });
    } else if (route.query.newRequest) {
      router.replace({
        name: 'crm_backoffice_new',
        params: { accountId: route.params.accountId },
      });
    }
  },
  { immediate: true }
);
</script>

<template>
  <div
    class="flex h-full min-w-0 flex-col bg-n-slate-2 text-n-slate-12"
    :class="crmControlClasses"
  >
    <header class="shrink-0 border-b border-n-weak bg-n-solid-2 px-4 py-3">
      <div class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-3">
          <span class="i-lucide-settings-2 size-8 text-emerald-600" />
          <div>
            <h1 class="text-lg font-bold">{{ text('MODULE') }}</h1>
            <p class="text-xs text-n-slate-11">{{ text('TITLE') }}</p>
          </div>
        </div>
        <RouterLink
          :to="{ name: 'crm_backoffice_new' }"
          class="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white"
        >
          {{ text('NEW_REQUEST') }}
        </RouterLink>
      </div>
      <ModuleTabs
        class="mt-3"
        :label="text('NAVIGATION')"
        :items="primary"
        :groups="navigationGroups"
        :active-key="
          route.params.requestId || route.name === 'crm_backoffice_new'
            ? 'requests'
            : section
        "
      />
    </header>
    <main
      :key="route.fullPath"
      class="min-h-0 flex-1 overflow-auto p-4"
    >
      <ModuleSegmentFilter
        v-if="
          !route.params.requestId &&
          route.name !== 'crm_backoffice_new' &&
          !['signature', 'requirements'].includes(section)
        "
        module-key="backoffice"
      />
      <BackofficeRequest360 v-if="route.params.requestId" />
      <BackofficeNewRequest v-else-if="route.name === 'crm_backoffice_new'" />
      <SignatureSettings v-else-if="section === 'signature'" />
      <template v-else-if="section === 'requirements'">
        <BackofficeRequirementSettings v-if="canManageRequirements" />
        <p
          v-else
          role="status"
        >
          {{ text('REQUIREMENTS.ACCESS_REQUIRED') }}
        </p>
      </template>
      <BackofficeOverview
        v-else-if="['overview', 'reports'].includes(section)"
        :report="section === 'reports'"
      />
      <BackofficeWorklist
        v-else
        :key="section"
        :mine="section === 'mine'"
        :section="section"
      />
    </main>
  </div>
</template>
