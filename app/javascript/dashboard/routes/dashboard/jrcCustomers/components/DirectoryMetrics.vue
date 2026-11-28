<script setup>
import { useI18n } from 'vue-i18n';

defineProps({ cards: { type: Array, required: true } });
const { n } = useI18n();
const tones = [
  'bg-n-blue-3 text-n-blue-11',
  'bg-n-teal-3 text-n-teal-11',
  'bg-n-amber-3 text-n-amber-11',
  'bg-n-violet-3 text-n-violet-11',
];
</script>

<template>
  <dl class="grid grid-cols-2 gap-3 lg:grid-cols-4">
    <div
      v-for="({ label, value, icon }, index) in cards"
      :key="label"
      class="relative isolate flex min-h-20 items-center gap-3 overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 px-3 py-3 shadow-sm sm:px-4"
    >
      <span
        aria-hidden="true"
        :class="tones[index]"
        class="absolute -bottom-14 -end-8 -z-10 size-32 rotate-[-15deg] rounded-[40%] opacity-65"
      />
      <span
        aria-hidden="true"
        :class="tones[index]"
        class="grid size-9 shrink-0 place-items-center rounded-xl sm:size-11"
      >
        <span
          :class="icon"
          class="size-5"
        />
      </span>
      <div class="min-w-0">
        <dt class="text-xs font-medium text-n-slate-11">{{ label }}</dt>
        <dd
          class="text-2xl font-bold leading-tight tabular-nums text-n-slate-12"
        >
          {{ typeof value === 'number' ? n(value) : '—' }}
        </dd>
      </div>
    </div>
  </dl>
</template>
