<script>
export default {
  props: {
    label: {
      type: String,
      required: true,
    },
    value: {
      type: [String, Number],
      required: true,
    },
    toolTip: {
      type: String,
      required: true,
    },
    isLoading: {
      type: Boolean,
      default: false,
    },
  },
};
</script>

<template>
  <div
    class="flex min-w-0 flex-col items-start justify-center gap-2 rounded-2xl border border-n-weak p-4 shadow-sm sm:p-5"
  >
    <span
      class="inline-flex items-center gap-1 text-sm font-medium text-n-slate-11"
    >
      {{ label }}
      <fluent-icon
        v-tooltip.right="toolTip"
        size="14"
        icon="information"
        type="outline"
        class="flex flex-shrink-0 text-sm font-normal sm:font-medium text-n-slate-10"
      />
    </span>
    <div
      v-if="isLoading"
      class="w-12 h-6 mb-0.5 rounded-md bg-n-slate-3 animate-pulse"
    />

    <span
      v-else
      class="text-3xl font-semibold tracking-tight text-n-slate-12 tabular-nums"
    >
      {{ value }}
    </span>
  </div>
</template>
