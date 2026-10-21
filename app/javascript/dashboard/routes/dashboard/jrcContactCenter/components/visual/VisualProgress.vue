<script setup>
defineProps({
  label: { type: String, required: true },
  value: { type: [Number, String], required: true },
  detail: { type: String, default: '' },
  tone: { type: String, default: 'blue' },
});

const bars = {
  blue: 'bg-n-blue-9',
  teal: 'bg-n-teal-9',
  violet: 'bg-n-iris-9',
  amber: 'bg-n-amber-9',
  ruby: 'bg-n-ruby-9',
  emerald: 'bg-emerald-600',
};

const widths = [
  'w-0',
  'w-[10%]',
  'w-1/5',
  'w-[30%]',
  'w-2/5',
  'w-1/2',
  'w-3/5',
  'w-[70%]',
  'w-4/5',
  'w-[90%]',
  'w-full',
];

const widthClass = value => {
  const index = Math.max(0, Math.min(10, Math.round(Number(value) / 10)));
  return widths[index];
};
</script>

<template>
  <div>
    <div class="mb-2 flex items-end justify-between gap-3">
      <div>
        <p class="text-sm font-medium text-n-slate-12">{{ label }}</p>
        <p v-if="detail" class="mt-0.5 text-xs text-n-slate-10">{{ detail }}</p>
      </div>
      <strong class="text-sm text-n-slate-12">{{
        $t('JRC_CONTACT_CENTER.VISUAL.PERCENTAGE', { value })
      }}</strong>
    </div>
    <div class="h-2 overflow-hidden rounded-full bg-n-alpha-2">
      <div
        class="h-full rounded-full transition-all"
        :class="[bars[tone] || bars.blue, widthClass(value)]"
      />
    </div>
  </div>
</template>
