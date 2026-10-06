<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store.js';
import Icon from 'next/icon/Icon.vue';
import SidebarNewBadge from './SidebarNewBadge.vue';

const props = defineProps({
  to: { type: [Object, String], default: '' },
  label: { type: String, default: '' },
  icon: { type: [String, Object], default: '' },
  expandable: { type: Boolean, default: false },
  isExpanded: { type: Boolean, default: false },
  isActive: { type: Boolean, default: false },
  hasActiveChild: { type: Boolean, default: false },
  getterKeys: { type: Object, default: () => ({}) },
  disabled: { type: Boolean, default: false },
  newBadge: { type: Boolean, default: false },
});

const emit = defineEmits(['toggle']);

const showBadge = useMapGetter(props.getterKeys.badge);
const dynamicCount = useMapGetter(props.getterKeys.count);
const count = computed(() =>
  dynamicCount.value > 99 ? '99+' : dynamicCount.value
);
</script>

<template>
  <component
    :is="to && !disabled && !expandable ? 'router-link' : 'button'"
    class="flex items-center gap-2 px-2.5 py-2 rounded-xl h-10 min-w-0 transition-colors"
    role="button"
    draggable="false"
    :type="expandable || !to || disabled ? 'button' : undefined"
    :aria-expanded="expandable ? isExpanded : undefined"
    :aria-disabled="disabled || undefined"
    :to="disabled || expandable ? undefined : to"
    :title="label"
    :class="{
      'bg-sidebar-active text-white font-medium shadow-[0_6px_18px_rgba(8,124,240,0.28)]':
        isActive && !hasActiveChild,
      'bg-white/10 text-white font-medium': hasActiveChild,
      'text-sidebar-foreground hover:bg-white/10 hover:text-white':
        !isActive && !hasActiveChild && !disabled,
      'cursor-not-allowed text-sidebar-muted': disabled,
    }"
    @click.stop="disabled ? undefined : emit('toggle')"
  >
    <div v-if="icon" class="relative flex items-center gap-2">
      <Icon v-if="icon" :icon="icon" class="size-[18px]" />
      <span
        v-if="showBadge"
        class="size-2 -top-px ltr:-right-px rtl:-left-px bg-n-brand absolute rounded-full border border-n-solid-2"
      />
    </div>
    <div
      class="flex items-center gap-1.5 flex-grow justify-between min-w-0 flex-1"
    >
      <span class="truncate text-sm font-medium text-inherit">
        {{ label }}
      </span>
      <SidebarNewBadge v-if="newBadge" />
      <span
        v-if="dynamicCount && !expandable"
        class="inline-grid h-5 min-w-5 place-items-center rounded-full bg-white/15 px-1 text-xxs font-medium leading-3 text-white flex-shrink-0"
      >
        {{ count }}
      </span>
    </div>
    <span
      class="grid size-3 shrink-0 place-items-center"
      data-testid="sidebar-trailing-slot"
    >
      <span
        v-if="expandable"
        class="i-lucide-chevron-down size-3"
        :class="{ 'rotate-180': isExpanded }"
      />
    </span>
  </component>
</template>
