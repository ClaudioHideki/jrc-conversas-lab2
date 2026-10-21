<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  icon: { type: String, default: '' },
  flush: { type: Boolean, default: false },
});
</script>

<template>
  <section
    class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
  >
    <header
      class="flex flex-wrap items-start justify-between gap-3 border-b border-n-weak px-4 py-3.5 sm:px-5"
    >
      <div class="flex min-w-0 items-start gap-3">
        <span
          v-if="icon"
          class="grid size-9 shrink-0 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11"
        >
          <Icon :icon="icon" class="size-4" />
        </span>
        <div class="min-w-0">
          <h3 class="break-words text-sm font-semibold text-n-slate-12">
            {{ title }}
          </h3>
          <p v-if="subtitle" class="mt-0.5 text-xs text-n-slate-10">
            {{ subtitle }}
          </p>
        </div>
      </div>
      <slot name="actions" />
    </header>
    <div :class="flush ? '' : 'p-4 sm:p-5'">
      <slot />
    </div>
  </section>
</template>
