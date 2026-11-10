<script setup>
defineProps({ status: { type: Object, required: true } });
const colors = {
  open: 'bg-blue-100 text-blue-800',
  waiting: 'bg-amber-100 text-amber-800',
  resolved: 'bg-emerald-100 text-emerald-800',
  closed: 'bg-emerald-100 text-emerald-800',
  cancelled: 'bg-slate-100 text-slate-700',
};
</script>

<template>
  <span
    class="inline-flex shrink-0 items-center gap-2 rounded-full px-4 py-2 text-sm font-semibold"
    :class="colors[status.phase] || colors.open"
  >
    <span
      class="h-2 w-2 rounded-full bg-current"
      aria-hidden="true"
    />
    {{ status.name }}
  </span>
</template>
