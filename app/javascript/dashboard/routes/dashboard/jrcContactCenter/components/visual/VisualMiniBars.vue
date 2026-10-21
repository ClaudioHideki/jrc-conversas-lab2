<script setup>
defineProps({
  values: { type: Array, default: () => [] },
  tone: { type: String, default: 'blue' },
});

const bars = {
  blue: 'bg-n-blue-8',
  teal: 'bg-n-teal-8',
  violet: 'bg-n-iris-8',
  amber: 'bg-n-amber-8',
  ruby: 'bg-n-ruby-8',
  emerald: 'bg-emerald-500',
};

const heights = [
  'h-2',
  'h-3',
  'h-4',
  'h-5',
  'h-6',
  'h-8',
  'h-10',
  'h-12',
  'h-14',
  'h-16',
  'h-20',
];

const heightClass = value => {
  const index = Math.max(0, Math.min(10, Math.round(Number(value) / 10)));
  return heights[index];
};
</script>

<template>
  <div class="flex h-20 items-end gap-1.5" aria-hidden="true">
    <span
      v-for="(value, index) in values"
      :key="index"
      class="min-w-0 flex-1 rounded-t-md opacity-80 transition hover:opacity-100"
      :class="[bars[tone] || bars.blue, heightClass(value)]"
    />
  </div>
</template>
