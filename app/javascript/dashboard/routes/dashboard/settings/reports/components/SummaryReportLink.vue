<script setup>
import { computed } from 'vue';
const props = defineProps({
  row: {
    type: Object,
    required: true,
  },
});

const routeName = computed(() => `${props.row.original.type}_reports_show`);
const appearance = {
  agent: {
    icon: 'i-lucide-user-round',
    tone: 'bg-n-violet-3 text-n-violet-11',
  },
  inbox: { icon: 'i-lucide-inbox', tone: 'bg-n-blue-3 text-n-blue-11' },
  team: { icon: 'i-lucide-users-round', tone: 'bg-n-teal-3 text-n-teal-11' },
  label: { icon: 'i-lucide-tag', tone: 'bg-n-violet-3 text-n-violet-11' },
};
const presentation = computed(() => appearance[props.row.original.type]);
</script>

<template>
  <router-link
    :to="{ name: routeName, params: { id: row.original.id } }"
    class="inline-flex items-center gap-2 font-semibold text-n-slate-12 hover:text-n-brand hover:underline"
  >
    <span
      class="grid size-8 shrink-0 place-items-center rounded-lg"
      :class="presentation?.tone"
      aria-hidden="true"
    >
      <span class="size-4" :class="presentation?.icon" />
    </span>
    {{ row.original.name }}
  </router-link>
</template>
