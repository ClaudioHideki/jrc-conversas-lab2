<script setup>
defineProps({ items: { type: Array, required: true } });
const colors = [
  'bg-n-blue-2 text-n-blue-11',
  'bg-n-teal-2 text-n-teal-11',
  'bg-n-amber-2 text-n-amber-11',
  'bg-n-violet-2 text-n-violet-11',
];
</script>

<template>
  <div class="my-4 grid grid-cols-2 gap-3 xl:grid-cols-4">
    <article
      v-for="(item, index) in items"
      :key="item.label"
      class="min-w-0 rounded-xl border border-n-weak p-4"
      :class="colors[index % colors.length]"
    >
      <h3 class="text-xs font-medium">{{ item.label }}</h3>
      <p class="my-2 text-2xl font-semibold">
        {{ item.value == null ? '—' : item.value }}
      </p>
      <p
        v-if="item.help"
        class="text-xs"
      >
        {{ item.help }}
      </p>
    </article>
  </div>
</template>
