<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import ModuleTabs from 'dashboard/components-next/navigation/ModuleTabs.vue';
import ModuleSegmentFilter from '../jrcCustomers/components/ModuleSegmentFilter.vue';
import { areaForScreen, visibleAreas } from './navigation';
import { relationshipTabClasses } from './tabClasses';
import { message } from './definitions';
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const metadata = ref(null);
const error = ref('');
const screen = computed(() =>
  String(route.name).replace('jrc_relationship_', '')
);
const area = computed(() => areaForScreen(screen.value));
const supportsSegment = key =>
  !['settings', 'playbooks', 'survey_admin'].includes(key);
const link = key => ({
  name: `jrc_relationship_${key}`,
  params: { accountId: route.params.accountId },
  query: {
    ...(route.query.assignment_id
      ? { assignment_id: route.query.assignment_id }
      : {}),
    ...(supportsSegment(key) && route.query.customer_segment_id
      ? { customer_segment_id: route.query.customer_segment_id }
      : {}),
    ...(supportsSegment(key) && route.query.portfolio_group_id
      ? { portfolio_group_id: route.query.portfolio_group_id }
      : {}),
  },
});
const items = computed(() =>
  visibleAreas(metadata.value).map(item => ({
    ...item,
    label: t(`RELATIONSHIP.V2.AREAS.${item.key}`),
    to: link(item.key),
  }))
);
const secondary = computed(() =>
  (area.value?.screens || [])
    .filter(
      key => key !== 'survey_admin' || metadata.value?.can_administer_surveys
    )
    .map(key => ({
      key,
      tone: area.value.tone,
      icon: 'i-lucide-circle-small',
      label: t(`RELATIONSHIP.SCREENS.${key}`),
      to: link(key),
    }))
);
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => route.name,
  ],
  async (_, __, cleanup) => {
    const controller = new AbortController();
    cleanup(() => controller.abort());
    metadata.value = null;
    error.value = '';
    try {
      const { data } = await API.metadata(route.params.accountId, {
        signal: controller.signal,
      });
      if (!controller.signal.aborted) metadata.value = data;
    } catch (err) {
      if (!controller.signal.aborted) error.value = message(err);
    }
  },
  { immediate: true }
);
</script>

<template>
  <main class="flex h-full min-w-0 flex-col bg-n-solid-1 text-n-slate-12">
    <header
      class="shrink-0 space-y-3 border-b border-n-violet-6 bg-n-violet-2 px-5 py-4"
    >
      <div class="flex items-center gap-3">
        <span
          class="i-lucide-heart-handshake size-9 text-n-violet-11"
          aria-hidden="true"
        />
        <div>
          <h1 class="text-xl font-semibold">{{ t('RELATIONSHIP.TITLE') }}</h1>
          <p class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.V2.PURPOSE') }}
          </p>
        </div>
      </div>
      <p
        v-if="error"
        role="alert"
        class="text-n-ruby-11"
      >
        {{ error }}
      </p>
      <ModuleTabs
        v-if="metadata"
        :label="t('RELATIONSHIP.TITLE')"
        :items="items"
        :tab-classes="relationshipTabClasses"
        :active-key="area?.key || ''"
      />
      <ModuleTabs
        v-if="metadata && secondary.length > 1"
        :label="t('RELATIONSHIP.V2.CONTEXT_NAV')"
        :items="secondary"
        :tab-classes="relationshipTabClasses"
        :active-key="screen"
      />
    </header>
    <ModuleSegmentFilter
      v-if="metadata && supportsSegment(screen)"
      module-key="relationship"
    />
    <RouterView
      :key="`${route.params.accountId}:${store.getters.getCurrentUserID}:${route.name}`"
    />
  </main>
</template>
