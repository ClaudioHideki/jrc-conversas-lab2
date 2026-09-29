<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed } from 'vue';
import KanbanCard from './KanbanCard.vue';
import CrmValueDisplay from '../shared/CrmValueDisplay.vue';

const props = defineProps({
  stage: { type: Object, required: true },
  deals: { type: Array, required: true },
});

defineEmits(['dragStart', 'dragEnd', 'dragOver', 'drop']);

const dealCount = computed(() => props.deals.length);
const financialSum = computed(() =>
  props.deals.reduce((sum, deal) => sum + (deal.value_cents || 0), 0)
);
const weightedSum = computed(() =>
  props.deals.reduce(
    (sum, deal) =>
      sum + ((deal.value_cents || 0) * (props.stage.probability || 100)) / 100,
    0
  )
);
const overdueCount = computed(
  () =>
    props.deals.filter(deal => deal.overdue || deal.next_activity?.is_overdue)
      .length
);
const stageAccent = computed(() => {
  if (props.stage.is_won) return 'bg-n-teal-9';
  if (props.stage.is_lost) return 'bg-n-ruby-9';
  if (Number(props.stage.probability) >= 70) return 'bg-n-blue-9';
  if (Number(props.stage.probability) >= 40) return 'bg-n-iris-9';
  return 'bg-n-amber-9';
});
</script>

<template>
  <div
    class="flex min-w-[320px] max-w-[320px] flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-alpha-1 shadow-sm"
    @dragover="$emit('dragOver', $event)"
    @drop="$emit('drop', $event)"
  >
    <div class="border-b border-n-weak bg-n-solid-2 p-4">
      <div class="-mx-4 -mt-4 mb-4 h-1.5" :class="stageAccent" />
      <div class="flex justify-between items-center mb-2">
        <h3
          class="font-bold text-n-slate-12 text-sm truncate"
          :title="stage.name"
        >
          {{ stage.name }}
        </h3>
        <span
          class="rounded-full bg-n-alpha-3 px-2.5 py-1 text-xs font-bold text-n-slate-11"
          >{{ dealCount }}</span
        >
      </div>
      <div class="text-xs text-n-slate-10 flex flex-col gap-1">
        <div class="flex justify-between">
          <span>Total:</span>
          <CrmValueDisplay
            :cents="financialSum"
            class="font-medium text-n-slate-11"
          />
        </div>
        <div class="flex justify-between">
          <span>Ponderado:</span>
          <CrmValueDisplay
            :cents="weightedSum"
            class="font-medium text-n-slate-11"
          />
        </div>
        <div
          v-if="overdueCount > 0"
          class="flex justify-between text-n-ruby-11 mt-1 font-medium"
        >
          <span>Atrasados:</span>
          <span>{{ overdueCount }}</span>
        </div>
      </div>
    </div>

    <div class="min-h-[150px] flex-1 overflow-y-auto p-3">
      <KanbanCard
        v-for="deal in deals"
        :key="deal.id"
        :deal="deal"
        draggable="true"
        @dragstart="$emit('dragStart', $event, deal)"
        @dragend="$emit('dragEnd', $event)"
      />
      <div
        v-if="!deals.length"
        class="mt-2 rounded-xl border-2 border-dashed border-n-weak bg-n-solid-2 p-6 text-center text-xs text-n-slate-9"
      >
        Nenhum negócio nesta etapa
      </div>
    </div>
  </div>
</template>
