<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';
defineProps({ title: { type: String, default: '' }, icon: { type: String, default: '' } });
</script>
<template>
  <section class="sd-panel">
    <header v-if="title" class="sd-panel-heading">
      <div class="flex items-center gap-2 min-w-0">
        <Icon v-if="icon" :icon="icon" class="size-4 text-n-blue-11 flex-shrink-0" />
        <h2 class="text-sm font-semibold text-n-slate-12 m-0">
          {{ title }}
        </h2>
      </div>
      <slot name="actions"><slot name="action" /></slot>
    </header>
    <div class="sd-panel-body">
      <slot />
    </div>
  </section>
</template>
