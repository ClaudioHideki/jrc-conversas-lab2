<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
defineProps({ summary: { type: Object, default: null }, loading: Boolean });
const { t } = useI18n();
const cards = [
  {
    key: 'pending',
    icon: 'i-lucide-hourglass',
    color:
      'border-blue-100 bg-blue-50 dark:border-blue-900 dark:bg-blue-950/40',
    ink: 'text-blue-700 dark:text-blue-200',
  },
  {
    key: 'approved',
    icon: 'i-lucide-circle-check',
    color:
      'border-emerald-100 bg-emerald-50 dark:border-emerald-900 dark:bg-emerald-950/40',
    ink: 'text-emerald-700 dark:text-emerald-200',
  },
  {
    key: 'rejected',
    icon: 'i-lucide-circle-x',
    color:
      'border-rose-100 bg-rose-50 dark:border-rose-900 dark:bg-rose-950/40',
    ink: 'text-rose-700 dark:text-rose-200',
  },
  {
    key: 'due_today',
    icon: 'i-lucide-clock-3',
    color:
      'border-amber-100 bg-amber-50 dark:border-amber-900 dark:bg-amber-950/40',
    ink: 'text-amber-700 dark:text-amber-200',
  },
];
</script>
<template>
  <section
    :aria-label="t('JRC_APPROVALS.workspace.indicators')"
    :aria-busy="loading"
    class="grid min-w-0 grid-cols-2 gap-3 xl:grid-cols-4"
  >
    <article
      v-for="card in cards"
      :key="card.key"
      class="flex min-w-0 items-center gap-3 rounded-xl border p-3 sm:p-4"
      :class="card.color"
    >
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-solid-2"
        :class="card.ink"
        ><Icon
          :icon="card.icon"
          class="size-5"
      /></span>
      <div class="min-w-0">
        <p
          class="text-2xl font-bold leading-tight text-n-slate-12"
          :data-metric="card.key"
        >
          {{
            typeof summary?.[card.key] === 'number' ? summary[card.key] : '—'
          }}
        </p>
        <p class="break-words text-xs text-n-slate-11 sm:text-sm">
          {{ t(`JRC_APPROVALS.workspace.metrics.${card.key}`) }}
        </p>
      </div>
    </article>
    <p class="col-span-full text-xs text-n-slate-11">
      {{ t('JRC_APPROVALS.workspace.indicatorScope')
      }}<span v-if="summary?.time_zone"> · {{ summary.time_zone }}</span>
    </p>
  </section>
</template>
