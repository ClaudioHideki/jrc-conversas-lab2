<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import PortalIcon from './PortalIcon.vue';
import PortalHeading from './PortalHeading.vue';
import { portalKnowledge } from '../../widget/helpers/serviceDeskPortal';
import { request, errorKey } from './client';
const { t } = useI18n();
const query = ref('');
const articles = ref([]);
const error = ref('');
const busy = ref(false);
const load = async () => {
  busy.value = true;
  articles.value = [];
  error.value = '';
  try {
    articles.value = portalKnowledge(
      await request(
        `/portal/api/conhecimento?${new URLSearchParams({ q: query.value })}`
      )
    );
  } catch (failure) {
    error.value = errorKey(failure);
  } finally {
    busy.value = false;
  }
};
onMounted(load);
</script>

<template>
  <section class="space-y-6">
    <PortalHeading
      icon="book"
      :title="t('PORTAL.KNOWLEDGE')"
      :subtitle="t('PORTAL.KNOWLEDGE_SEARCH')"
    />
    <form
      class="flex flex-wrap gap-3 rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414] p-5"
      @submit.prevent="load"
    >
      <label class="min-w-0 flex-1 text-sm">
        {{ t('PORTAL.KNOWLEDGE_SEARCH') }}
        <input
          v-model="query"
          maxlength="200"
          class="mt-2 w-full rounded-xl border border-blue-200 shadow-inner focus:border-blue-500 focus:ring-2 focus:ring-blue-200 p-3"
        />
      </label>
      <button
        :disabled="busy"
        class="flex items-center gap-2 self-end rounded-xl bg-gradient-to-b from-blue-500 to-blue-800 shadow-md hover:from-blue-600 hover:to-blue-900 px-5 py-3 text-sm font-semibold text-white"
      >
        <PortalIcon name="search" />
        {{ t('PORTAL.FILTER') }}
      </button>
    </form>
    <p
      v-if="error"
      role="alert"
    >
      {{ t(error) }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('PORTAL.LOADING') }}
    </p>
    <p
      v-else-if="!articles.length"
      class="flex min-h-80 flex-col items-center justify-center gap-6 rounded-2xl border border-blue-200/80 bg-white/90 p-8 text-center text-xl font-bold text-slate-900 shadow-sm"
    >
      <span class="rounded-full bg-blue-50 p-8 text-blue-700">
        <PortalIcon
          name="book"
          class="h-20 w-20"
        />
      </span>
      {{ t('PORTAL.KNOWLEDGE_EMPTY') }}
    </p>
    <a
      v-for="article in articles"
      :key="article.id"
      :href="article.path"
      class="block rounded-2xl border border-blue-200/80 bg-white/90 shadow-[0_3px_12px_#0754a414] p-6 hover:border-blue-300"
    >
      <h2 class="font-semibold">{{ article.title }}</h2>
      <p class="mt-2 text-sm text-slate-500">{{ article.description }}</p>
    </a>
  </section>
</template>
