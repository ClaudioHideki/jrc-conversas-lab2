<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import ModulePage from './ModulePage.vue';
import TeamPanel from './TeamPanel.vue';
import { buttonClass, message } from './definitions';
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const metadata = ref(null);
const error = ref('');
const section = computed(() => route.query.section || 'customers');
watch(
  [() => route.params.accountId, () => store.getters.getCurrentUserID],
  async (_, __, cleanup) => {
    const controller = new AbortController();
    cleanup(() => controller.abort());
    metadata.value = null;
    error.value = '';
    try {
      const result = await API.metadata(route.params.accountId, {
        signal: controller.signal,
      });
      if (!controller.signal.aborted) metadata.value = result.data;
    } catch (err) {
      if (!controller.signal.aborted) error.value = message(err);
    }
  },
  { immediate: true }
);
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <nav
      v-if="metadata"
      class="flex shrink-0 flex-wrap gap-2 px-5 pt-4"
      :aria-label="t('RELATIONSHIP.V2.AREAS.portfolio')"
    >
      <button
        v-for="key in ['customers', ...(metadata.can_team ? ['team'] : [])]"
        :key="key"
        type="button"
        :class="[
          buttonClass,
          section === key &&
            'border-teal-500 bg-teal-50 text-teal-900 dark:bg-teal-950 dark:text-teal-200',
        ]"
        :aria-pressed="section === key"
        @click="router.replace({ query: { ...route.query, section: key } })"
      >
        {{ t(`RELATIONSHIP.V2.PORTFOLIO.${key}`) }}
      </button>
    </nav>
    <p
      v-if="error"
      role="alert"
      class="p-5 text-n-ruby-11"
    >
      {{ error }}
    </p>
    <div
      v-if="metadata && section === 'team' && metadata.can_team"
      class="min-h-0 flex-1 overflow-y-auto p-5"
    >
      <TeamPanel />
    </div>
    <ModulePage
      v-else-if="metadata"
      screen="portfolio"
    />
  </div>
</template>
