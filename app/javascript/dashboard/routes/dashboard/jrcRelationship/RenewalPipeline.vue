<script setup>
import { useI18n } from 'vue-i18n';
import { buttonClass } from './definitions';
defineProps({
  windows: { type: Object, default: () => ({}) },
  selected: { type: String, default: '' },
});
const emit = defineEmits(['filter']);
const { t } = useI18n();
const keys = ['120', '90', '60', '30', '15', 'overdue', 'later'];
</script>

<template>
  <section
    data-testid="renewal-pipeline"
    class="space-y-2"
  >
    <h3 class="font-semibold">{{ t('RELATIONSHIP.RENEWAL_PIPELINE') }}</h3>
    <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-7">
      <button
        v-for="key in keys"
        :key="key"
        :class="buttonClass"
        class="flex-col p-3"
        :aria-pressed="selected === key"
        @click="emit('filter', selected === key ? '' : key)"
      >
        <span>{{ t(`RELATIONSHIP.WINDOWS.${key}`) }}</span
        ><strong class="text-xl">{{ windows[key] ?? 0 }}</strong>
      </button>
    </div>
    <p class="text-xs text-n-slate-11">
      {{ t('RELATIONSHIP.RENEWAL_WINDOW_EXPLANATION') }}
    </p>
  </section>
</template>
