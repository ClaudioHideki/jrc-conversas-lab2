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
    class="min-h-0 max-h-[40dvh] grid-cols-3 gap-1 overflow-y-auto overscroll-contain p-2 lg:max-h-none lg:flex-1 lg:flex-col lg:p-1 xl:p-2"
  >
    <button
      v-for="action in actions"
      :key="action.key"
      type="button"
      :aria-label="t(`JRC_HOME.ACTIONS.${action.key}`)"
      :title="t(`JRC_HOME.ACTIONS.${action.key}`)"
      class="flex min-h-16 min-w-0 shrink-0 flex-col items-center justify-center gap-1.5 rounded-xl px-2 py-2 text-center transition hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
      @click="$emit('select', action.key)"
    >
      <span
        class="grid size-10 place-content-center rounded-xl border"
        :class="homeTones[action.tone]"
        ><span :class="action.icon" class="size-5" aria-hidden="true"
      /></span>
      <span
        class="max-w-20 break-words text-xs font-medium text-n-slate-12 lg:sr-only xl:not-sr-only"
        >{{ t(`JRC_HOME.ACTIONS.${action.key}`) }}</span
      >
    </button>
  </nav>
</template>
