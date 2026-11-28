<script setup>
import { inject } from 'vue';

defineProps({ title: { type: String, required: true } });
const inCrmShell = inject('crmListingHeader', false);
</script>

<template>
  <Teleport v-if="inCrmShell" to="#crm-listing-actions" defer>
    <slot />
  </Teleport>
  <header v-else class="flex flex-wrap items-center justify-between gap-2">
    <h2 class="text-xl font-bold text-n-slate-12">{{ title }}</h2>
    <div class="flex flex-wrap gap-2"><slot /></div>
  </header>
</template>
