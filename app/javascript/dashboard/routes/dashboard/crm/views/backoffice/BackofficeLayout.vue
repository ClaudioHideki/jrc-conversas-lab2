<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import BackofficeOverview from './BackofficeOverview.vue';
import BackofficeWorklist from './BackofficeWorklist.vue';
import BackofficeRequest360 from './BackofficeRequest360.vue';
import BackofficeView from './BackofficeView.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

const route = useRoute();
const viewport = ref(null);
watch(
  () => route.fullPath,
  () => {
    viewport.value.scrollTop = 0;
  },
  { flush: 'post' }
);
const { text } = useBackofficePresentation();
const sections = [
  'overview',
  'mine',
  'requests',
  'process',
  'docs',
  'contracts',
  'implement',
  'provision',
  'finance',
  'issues',
  'approvals',
  'changes',
  'sla',
  'reports',
];
const section = computed(() => {
  if (route.params.section === 'queues') return 'requests';
  return sections.includes(route.params.section)
    ? route.params.section
    : 'overview';
});
</script>

<template>
  <div
    ref="viewport"
    class="h-full overflow-auto bg-n-slate-2 p-4 sm:p-6"
  >
    <header
      class="mb-5 flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-emerald-200 bg-n-solid-2 p-5 shadow-sm"
    >
      <div>
        <p
          class="text-xs font-semibold uppercase tracking-wide text-emerald-700"
        >
          {{ text('EYEBROW') }}
        </p>
        <h1 class="mt-1 text-2xl font-bold text-n-slate-12">
          {{ text('TITLE') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">{{ text('SUBTITLE') }}</p>
      </div>
      <RouterLink
        :to="{
          name: 'crm_backoffice',
          params: { section: 'process' },
          query: { newRequest: '1' },
        }"
        class="inline-block rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold text-white"
      >
        {{ text('NEW_REQUEST') }}
      </RouterLink>
    </header>
    <div class="grid items-start gap-5 xl:grid-cols-[215px_minmax(0,1fr)]">
      <nav
        :aria-label="text('NAVIGATION')"
        class="flex gap-1 overflow-x-auto rounded-2xl border border-n-weak bg-n-solid-2 p-2 shadow-sm xl:sticky xl:top-0 xl:flex-col"
      >
        <RouterLink
          v-for="item in sections"
          :key="item"
          :to="{ name: 'crm_backoffice', params: { section: item } }"
          class="whitespace-nowrap rounded-xl px-3 py-2.5 text-sm font-semibold transition xl:whitespace-normal"
          :class="
            !route.params.requestId && section === item
              ? 'bg-emerald-600 text-white shadow-sm'
              : 'text-n-slate-11 hover:bg-n-slate-3'
          "
          :aria-current="
            !route.params.requestId && section === item ? 'page' : undefined
          "
        >
          {{ text(`NAV.${item}`) }}
        </RouterLink>
      </nav>
      <main class="min-w-0">
        <BackofficeRequest360
          v-if="route.params.requestId"
          :key="route.params.requestId"
        />
        <BackofficeOverview v-else-if="section === 'overview'" />
        <BackofficeWorklist
          v-else-if="['mine', 'requests'].includes(section)"
          :key="section"
          :mine="section === 'mine'"
        />
        <BackofficeView
          v-else
          :key="`${route.params.accountId}-${section}`"
          embedded
        />
      </main>
    </div>
  </div>
</template>
