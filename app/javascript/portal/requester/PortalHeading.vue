<script setup>
import PortalIcon from './PortalIcon.vue';
defineProps({
  title: { type: String, required: true },
  icon: { type: String, default: 'headset' },
  subtitle: { type: String, default: '' },
});
</script>

<template>
  <header
    class="flex min-w-0 flex-wrap items-center justify-between gap-5 py-2"
  >
    <div class="flex min-w-0 items-center gap-4">
      <span
        class="flex h-16 w-16 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-b from-sky-400 via-blue-600 to-blue-900 text-white shadow-md sm:h-20 sm:w-20"
      >
        <PortalIcon
          :name="icon"
          class="h-9 w-9 sm:h-10 sm:w-10"
        />
      </span>
      <div class="min-w-0">
        <h1
          class="break-words text-2xl font-bold tracking-tight text-slate-950 sm:text-3xl xl:text-4xl"
        >
          {{ title }}
        </h1>
        <p
          v-if="subtitle"
          class="mt-1 max-w-2xl text-sm leading-relaxed text-slate-700 sm:text-base"
        >
          {{ subtitle }}
        </p>
      </div>
    </div>
    <slot />
  </header>
</template>
