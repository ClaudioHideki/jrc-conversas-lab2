<script setup>
import { universityLink } from './university';

defineProps({ collapsed: { type: Boolean, default: false } });
</script>

<template>
  <li class="min-w-0 list-none">
    <a
      :href="universityLink.href"
      target="_blank"
      rel="noopener noreferrer"
      :title="universityLink.label"
      :aria-label="universityLink.label"
      class="flex min-h-10 items-center gap-2 rounded-xl text-sidebar-foreground transition-colors hover:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-sidebar-foreground"
      :class="collapsed ? 'size-10 justify-center' : 'px-3 py-2'"
    >
      <span
        :class="universityLink.icon"
        class="size-5 shrink-0 text-sidebar-secondary"
        aria-hidden="true"
      />
      <span v-if="!collapsed" class="truncate text-sm font-medium">{{
        universityLink.label
      }}</span>
      <span
        v-if="!collapsed"
        class="i-lucide-arrow-up-right ml-auto size-3.5 shrink-0 text-sidebar-secondary"
        aria-hidden="true"
      />
    </a>
  </li>
</template>
