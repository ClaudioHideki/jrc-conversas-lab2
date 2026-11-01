<script setup>
import { computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import BackofficeOverview from './BackofficeOverview.vue';
import BackofficeWorklist from './BackofficeWorklist.vue';
import BackofficeRequest360 from './BackofficeRequest360.vue';
import BackofficeNewRequest from './BackofficeNewRequest.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

const route = useRoute();
const router = useRouter();
const { text } = useBackofficePresentation();
const primary = ['overview', 'mine', 'requests'];
const groups = [
  {
    key: 'OPERATION',
    sections: ['process', 'docs', 'contracts', 'implement', 'provision'],
  },
  {
    key: 'CONTROL',
    sections: ['finance', 'issues', 'approvals', 'changes', 'sla', 'reports'],
  },
];
const sections = [...primary, ...groups.flatMap(group => group.sections)];
const section = computed(() =>
  sections.includes(
    route.params.section === 'queues' ? 'requests' : route.params.section
  )
    ? route.params.section
    : 'overview'
);
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
  <div class="flex h-full min-w-0 flex-col bg-n-slate-2">
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
      <nav
        :aria-label="text('NAVIGATION')"
        class="mt-3 flex flex-wrap gap-2"
      >
        <RouterLink
          v-for="item in primary"
          :key="item"
          :to="{ name: 'crm_backoffice', params: { section: item } }"
          class="rounded-lg border px-3 py-2 text-sm font-semibold"
          :class="
            !route.params.requestId &&
            route.name !== 'crm_backoffice_new' &&
            section === item
              ? 'border-emerald-600 bg-emerald-600 text-white'
              : 'border-n-weak text-n-slate-11 hover:bg-n-slate-3'
          "
          :aria-current="
            !route.params.requestId && section === item ? 'page' : undefined
          "
        >
          {{ text(`NAV.${item}`) }}
        </RouterLink>
        <details
          v-for="group in groups"
          :key="group.key"
          class="relative"
        >
          <summary
            class="cursor-pointer rounded-lg border px-3 py-2 text-sm font-semibold"
            :class="
              group.sections.includes(section)
                ? 'border-emerald-400 bg-emerald-50 text-emerald-900'
                : 'border-n-weak text-n-slate-11'
            "
          >
            {{ text(group.key) }}
          </summary>
          <div
            class="absolute left-0 top-full z-40 mt-1 w-60 rounded-xl border border-n-weak bg-n-solid-2 p-2 shadow-lg"
          >
            <RouterLink
              v-for="item in group.sections"
              :key="item"
              :to="{ name: 'crm_backoffice', params: { section: item } }"
              class="block rounded-lg px-3 py-2 text-sm hover:bg-n-slate-3"
              :class="{ 'font-bold text-emerald-700': section === item }"
              @click="$event.currentTarget.closest('details').open = false"
            >
              {{ text(`NAV.${item}`) }}
            </RouterLink>
          </div>
        </details>
      </nav>
    </header>
    <main
      :key="route.fullPath"
      class="min-h-0 flex-1 overflow-auto p-4"
    >
      <BackofficeRequest360 v-if="route.params.requestId" />
      <BackofficeNewRequest v-else-if="route.name === 'crm_backoffice_new'" />
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
