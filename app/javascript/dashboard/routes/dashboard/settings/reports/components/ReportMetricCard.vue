<script setup>
defineProps({
  label: {
    type: String,
    required: true,
  },
  value: {
    type: String,
    required: true,
  },
  infoText: {
    type: String,
    required: true,
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <div
    data-test-id="reportMetricContainer"
    class="min-w-0 rounded-2xl border border-n-weak p-4 shadow-sm sm:p-5"
    :class="{
      'grayscale pointer-events-none opacity-30': disabled,
    }"
  >
    <h3 class="flex items-center m-0 text-sm font-medium text-n-slate-11">
      <span data-test-id="reportMetricLabel">{{ label }}</span>
      <fluent-icon
        v-tooltip="infoText"
        data-test-id="reportMetricInfo"
        size="14"
        icon="info"
        class="text-n-slate-11 my-0 mx-1 mt-0.5"
      />
    </h3>
    <h4
      data-test-id="reportMetricValue"
      class="mb-0 mt-2 text-3xl font-semibold tracking-tight text-n-slate-12 tabular-nums"
    >
      {{ value }}
    </h4>
  </div>
</template>
