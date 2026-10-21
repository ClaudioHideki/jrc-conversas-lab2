<script setup>
defineProps({
  label: { type: String, required: true },
  tone: { type: String, default: 'slate' },
  dot: { type: Boolean, default: false },
});

const classes = {
  slate: 'border-n-weak bg-n-alpha-2 text-n-slate-11',
  blue: 'border-n-blue-5 bg-n-blue-2 text-n-blue-11',
  teal: 'border-n-teal-5 bg-n-teal-2 text-n-teal-11',
  amber: 'border-n-amber-5 bg-n-amber-2 text-n-amber-11',
  ruby: 'border-n-ruby-5 bg-n-ruby-2 text-n-ruby-11',
  violet: 'border-n-iris-5 bg-n-iris-2 text-n-iris-11',
  emerald: 'border-emerald-200 bg-emerald-50 text-emerald-700',
};

const dots = {
  slate: 'bg-n-slate-9',
  blue: 'bg-n-blue-9',
  teal: 'bg-n-teal-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
  violet: 'bg-n-iris-9',
  emerald: 'bg-emerald-600',
};
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-semibold"
    :class="classes[tone] || classes.slate"
  >
    <span
      v-if="dot"
      class="size-1.5 rounded-full"
      :class="dots[tone] || dots.slate"
    />
    {{ label }}
  </span>
</template>
