<script setup>
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { SCREENS } from './definitions';
const route = useRoute();
const { t } = useI18n();
</script>

<template>
  <main class="flex h-full min-w-0 flex-col bg-n-solid-1 text-n-slate-12">
    <header class="border-b border-n-weak px-6 py-4">
      <h1 class="text-xl font-semibold">{{ t('RELATIONSHIP.TITLE') }}</h1>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('RELATIONSHIP.SUBTITLE') }}
      </p>
      <nav
        class="mt-4 flex flex-wrap gap-2"
        :aria-label="t('RELATIONSHIP.TITLE')"
      >
        <RouterLink
          v-for="screen in SCREENS"
          :key="screen"
          class="rounded-lg px-3 py-2 text-sm hover:bg-n-alpha-2"
          active-class="bg-n-brand/10 font-semibold text-n-brand"
          :to="{
            name: `jrc_relationship_${screen}`,
            params: { accountId: route.params.accountId },
            query: route.query.assignment_id
              ? { assignment_id: route.query.assignment_id }
              : {},
          }"
        >
          {{ t(`RELATIONSHIP.SCREENS.${screen}`) }}
        </RouterLink>
      </nav>
    </header>
    <RouterView :key="`${route.params.accountId}:${route.name}`" />
  </main>
</template>
