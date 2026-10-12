<script setup>
import { computed } from 'vue';
const props = defineProps({
  value: { type: Number, required: true },
  maximum: { type: Number, required: true },
  label: { type: String, required: true },
});
const arc = computed(
  () =>
    `${Math.min(1, Math.max(0, props.value / Math.max(1, props.maximum))) * 100} 100`
);
</script>

<template>
  <span class="relative flex size-14 shrink-0 items-center justify-center">
    <svg viewBox="0 0 40 40" class="size-14 -rotate-90" aria-hidden="true">
      <circle
        cx="20"
        cy="20"
        r="16"
        fill="none"
        stroke="currentColor"
        stroke-width="3"
        class="text-n-alpha-2"
      />
      <circle
        cx="20"
        cy="20"
        r="16"
        fill="none"
        stroke="currentColor"
        stroke-width="3"
        stroke-linecap="round"
        pathLength="100"
        :stroke-dasharray="arc"
      />
    </svg>
    <strong
      class="absolute text-sm tabular-nums"
      :aria-label="`${label}: ${value}`"
      >{{ value }}</strong
    >
  </span>
</template>
