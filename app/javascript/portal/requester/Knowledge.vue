<script setup>
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
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
    <h1 class="text-2xl font-semibold text-slate-900">
      {{ t('PORTAL.KNOWLEDGE') }}
    </h1>
    <form
      class="flex flex-wrap gap-3 rounded-2xl border border-slate-200 bg-white p-5"
      @submit.prevent="load"
    >
      <label class="min-w-0 flex-1 text-sm">
        {{ t('PORTAL.KNOWLEDGE_SEARCH') }}
        <input
          v-model="query"
          maxlength="200"
          class="mt-2 w-full rounded-xl border border-slate-300 p-3"
        />
      </label>
      <button
        :disabled="busy"
        class="self-end rounded-xl bg-slate-900 px-5 py-3 text-sm font-semibold text-white"
      >
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
      class="rounded-2xl border border-slate-200 bg-white p-8 text-sm text-slate-500"
    >
      {{ t('PORTAL.KNOWLEDGE_EMPTY') }}
    </p>
    <a
      v-for="article in articles"
      :key="article.id"
      :href="article.path"
      class="block rounded-2xl border border-slate-200 bg-white p-6 hover:border-blue-300"
    >
      <h2 class="font-semibold">{{ article.title }}</h2>
      <p class="mt-2 text-sm text-slate-500">{{ article.description }}</p>
    </a>
  </section>
</template>
