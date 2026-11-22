<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({ modelValue: { type: Object, required: true } });
const { t } = useI18n();
const text = key => t(`JRC_CONTACT_CENTER.LOCAL_IVR.${key}`);
const nodes = computed(() => props.modelValue.nodes);
const edges = node => {
  if (node.type === 'calendar')
    return [
      {
        label: t('JRC_CONTACT_CENTER.IVR_CALENDAR.ON_OPEN'),
        target: node.on_open,
      },
      {
        label: t('JRC_CONTACT_CENTER.IVR_CALENDAR.ON_CLOSED'),
        target: node.on_closed,
      },
    ];
  if (node.type !== 'menu') return [];
  return [
    ...node.options.map(choice => ({
      label: `${text('DIGIT')} ${choice.digit || '—'}`,
      target: choice.target,
    })),
    { label: text('ON_TIMEOUT'), target: node.on_timeout },
    { label: text('ON_INVALID'), target: node.on_invalid },
  ];
};
const exists = id => nodes.value.some(node => node.id === id);
</script>

<template>
  <section
    v-if="nodes.length"
    :aria-label="text('MAP_TITLE')"
    class="min-w-0 space-y-3 rounded-xl border border-n-blue-6 bg-n-blue-2 p-3"
    data-ivr-map
  >
    <h3 class="flex items-center gap-2 font-semibold text-n-slate-12">
      <Icon icon="i-lucide-network" class="size-4 shrink-0 text-n-blue-11" />
      {{ text('MAP_TITLE') }}
    </h3>
    <p class="text-xs text-n-slate-11">{{ text('MAP_HINT') }}</p>
    <div class="grid min-w-0 gap-3 sm:grid-cols-2 lg:grid-cols-3">
      <article
        v-for="node in nodes"
        :key="node.id"
        :data-ivr-map-node="node.id"
        class="min-w-0 space-y-2 rounded-lg border border-n-weak bg-n-solid-1 p-3 text-sm text-n-slate-12"
      >
        <h4 class="break-all font-semibold">
          {{ node.id }} · {{ text(`TYPES.${node.type}`) }}
        </h4>
        <p
          v-if="node.id === modelValue.start"
          class="text-xs font-semibold text-n-blue-11"
        >
          {{ text('START') }}
        </p>
        <ul v-if="['menu', 'calendar'].includes(node.type)" class="space-y-2">
          <li
            v-for="(edge, index) in edges(node)"
            :key="index"
            class="flex min-w-0 flex-wrap items-center gap-1 text-xs"
          >
            <span class="break-words">{{ edge.label }}</span>
            <Icon icon="i-lucide-arrow-right" class="size-3 shrink-0" />
            <span
              class="break-all"
              :class="
                exists(edge.target) ? 'text-n-blue-11' : 'text-n-amber-11'
              "
              >{{
                exists(edge.target) ? edge.target : text('MAP_PENDING')
              }}</span
            >
          </li>
        </ul>
        <p v-else-if="node.type === 'queue'" class="break-all text-xs">
          {{ text('TYPES.queue') }} #{{ node.queue_id || '—' }}
        </p>
        <p v-else class="text-xs text-n-slate-11">{{ text('TYPES.end') }}</p>
      </article>
    </div>
  </section>
</template>
