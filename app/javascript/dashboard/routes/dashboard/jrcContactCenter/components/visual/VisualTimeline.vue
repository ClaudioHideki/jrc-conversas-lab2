<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';
import VisualStatusBadge from './VisualStatusBadge.vue';

defineProps({
  items: { type: Array, default: () => [] },
});
</script>

<template>
  <div class="space-y-0">
    <div
      v-for="(item, index) in items"
      :key="item.id || `${item.title}-${index}`"
      class="relative flex gap-3 pb-5 last:pb-0"
    >
      <div class="relative flex w-8 shrink-0 justify-center">
        <span
          v-if="index < items.length - 1"
          class="absolute bottom-0 top-8 w-px bg-n-weak"
        />
        <span
          class="relative grid size-8 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11 ring-4 ring-n-solid-2"
        >
          <Icon :icon="item.icon || 'i-lucide-circle-dot'" class="size-4" />
        </span>
      </div>
      <div class="min-w-0 flex-1 pt-1">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <p class="text-sm font-semibold text-n-slate-12">{{ item.title }}</p>
          <span class="text-xs text-n-slate-9">{{ item.time }}</span>
        </div>
        <p
          v-if="item.description"
          class="mt-1 text-xs leading-5 text-n-slate-10"
        >
          {{ item.description }}
        </p>
        <VisualStatusBadge
          v-if="item.status"
          class="mt-2"
          :label="item.status"
          :tone="item.tone || 'slate'"
        />
      </div>
    </div>
  </div>
</template>
