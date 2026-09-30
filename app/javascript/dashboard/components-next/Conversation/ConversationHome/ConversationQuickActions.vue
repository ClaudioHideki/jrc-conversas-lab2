<script setup>
import { useI18n } from 'vue-i18n';
import { homeTones } from './presentation';
defineProps({ actions: { type: Array, required: true } });
defineEmits(['select']);
const { t } = useI18n();
</script>

<template>
  <nav
    :aria-label="t('JRC_HOME.QUICK_ACTIONS')"
    class="flex shrink-0 gap-2 overflow-x-auto border-b border-n-weak bg-n-solid-2 p-2 xl:w-24 xl:flex-col xl:overflow-x-hidden xl:overflow-y-auto xl:border-b-0 xl:border-l xl:pb-24"
  >
    <button
      v-for="action in actions"
      :key="action.key"
      type="button"
      :aria-label="t(`JRC_HOME.ACTIONS.${action.key}`)"
      :title="t(`JRC_HOME.ACTIONS.${action.key}`)"
      class="flex min-h-16 min-w-20 shrink-0 flex-col items-center justify-center gap-1.5 rounded-xl px-2 py-2 text-center transition hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
      @click="$emit('select', action.key)"
    >
      <span
        class="grid size-10 place-content-center rounded-xl border"
        :class="homeTones[action.tone]"
        ><span :class="action.icon" class="size-5" aria-hidden="true"
      /></span>
      <span class="max-w-20 text-xs font-medium text-n-slate-12">{{
        t(`JRC_HOME.ACTIONS.${action.key}`)
      }}</span>
    </button>
  </nav>
</template>
