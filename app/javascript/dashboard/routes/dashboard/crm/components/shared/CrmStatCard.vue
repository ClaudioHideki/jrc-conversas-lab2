<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], required: true },
  detail: { type: String, default: '' },
  icon: { type: String, default: 'i-lucide-chart-no-axes-combined' },
  tone: {
    type: String,
    default: 'blue',
    validator: value =>
      ['blue', 'teal', 'iris', 'amber', 'ruby', 'slate'].includes(value),
  },
});

const toneClasses = {
  blue: {
    accent: 'bg-n-blue-9',
    icon: 'bg-n-blue-3 text-n-blue-11',
  },
  teal: {
    accent: 'bg-n-teal-9',
    icon: 'bg-n-teal-3 text-n-teal-11',
  },
  iris: {
    accent: 'bg-n-iris-9',
    icon: 'bg-n-iris-3 text-n-iris-11',
  },
  amber: {
    accent: 'bg-n-amber-9',
    icon: 'bg-n-amber-3 text-n-amber-11',
  },
  ruby: {
    accent: 'bg-n-ruby-9',
    icon: 'bg-n-ruby-3 text-n-ruby-11',
  },
  slate: {
    accent: 'bg-n-slate-8',
    icon: 'bg-n-alpha-3 text-n-slate-11',
  },
};
</script>

<template>
  <article
    class="relative overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
  >
    <span
      class="absolute inset-x-0 top-0 h-1"
      :class="toneClasses[tone].accent"
    />
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <p class="text-sm font-semibold text-n-slate-11">{{ label }}</p>
        <p
          class="mt-2 truncate text-2xl font-bold tabular-nums"
          :class="toneClasses[tone].icon.split(' ')[1]"
        >
          {{ value }}
        </p>
        <p v-if="detail" class="mt-1 text-xs text-n-slate-10">
          {{ detail }}
        </p>
      </div>
      <span
        class="flex size-10 shrink-0 items-center justify-center rounded-2xl"
        :class="toneClasses[tone].icon"
      >
        <i class="size-5" :class="icon" />
      </span>
    </div>
  </article>
</template>
