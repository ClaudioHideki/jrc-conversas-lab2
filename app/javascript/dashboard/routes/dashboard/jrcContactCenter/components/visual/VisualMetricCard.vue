<script setup>
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  detail: { type: String, default: '' },
  icon: { type: String, default: 'i-lucide-activity' },
  tone: { type: String, default: 'blue' },
  trend: { type: String, default: '' },
});

const toneClasses = {
  blue: {
    icon: 'bg-n-blue-3 text-n-blue-11',
    glow: 'from-n-blue-3/70 to-transparent',
  },
  teal: {
    icon: 'bg-n-teal-3 text-n-teal-11',
    glow: 'from-n-teal-3/70 to-transparent',
  },
  violet: {
    icon: 'bg-n-iris-3 text-n-iris-11',
    glow: 'from-n-iris-3/70 to-transparent',
  },
  amber: {
    icon: 'bg-n-amber-3 text-n-amber-11',
    glow: 'from-n-amber-3/70 to-transparent',
  },
  ruby: {
    icon: 'bg-n-ruby-3 text-n-ruby-11',
    glow: 'from-n-ruby-3/70 to-transparent',
  },
  emerald: {
    icon: 'bg-emerald-50 text-emerald-700',
    glow: 'from-emerald-50/80 to-transparent',
  },
};
</script>

<template>
  <article
    class="group relative overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
  >
    <div
      class="pointer-events-none absolute inset-x-0 top-0 h-16 bg-gradient-to-b opacity-0 transition group-hover:opacity-100"
      :class="toneClasses[tone]?.glow || toneClasses.blue.glow"
    />
    <div class="relative flex items-start justify-between gap-3">
      <div class="min-w-0">
        <p
          class="break-words text-xs font-semibold uppercase tracking-wide text-n-slate-10"
        >
          {{ label }}
        </p>
        <div class="mt-2 flex flex-wrap items-end gap-2">
          <strong class="text-2xl font-bold tracking-tight text-n-slate-12">
            {{ value }}
          </strong>
          <span
            v-if="trend"
            class="mb-0.5 rounded-full bg-n-alpha-2 px-2 py-0.5 text-[11px] font-semibold text-n-slate-11"
          >
            {{ trend }}
          </span>
        </div>
        <p v-if="detail" class="mt-1 break-words text-xs text-n-slate-10">
          {{ detail }}
        </p>
      </div>
      <span
        class="grid size-10 shrink-0 place-content-center rounded-xl"
        :class="toneClasses[tone]?.icon || toneClasses.blue.icon"
      >
        <Icon :icon="icon" class="size-5" />
      </span>
    </div>
  </article>
</template>
