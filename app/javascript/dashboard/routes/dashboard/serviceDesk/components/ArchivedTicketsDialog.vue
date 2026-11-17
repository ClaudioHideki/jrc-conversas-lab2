<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import TicketTable from './TicketTable.vue';
import State from './ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';

const props = defineProps({ query: { type: Object, required: true } });
const emit = defineEmits(['close', 'open', 'page']);
const { t } = useI18n();
const session = useServiceDesk();
const dialog = ref(null);
const key = 'tickets:archived';
const result = computed(() => session.resource(key));
const load = (background = false) =>
  session.load(key, 'tickets', props.query, null, { background });
watch([() => props.query, () => session.state.status], () => load(), {
  immediate: true,
  deep: true,
});
watch(
  () => session.operations?.state.revision,
  () => load(true)
);
onMounted(() => dialog.value?.showModal());
onBeforeUnmount(() => session.resetResource(key));
</script>

<template>
  <dialog
    ref="dialog"
    aria-labelledby="sd-archived-tickets-title"
    class="w-[calc(100%-2rem)] max-h-[90vh] max-w-7xl overflow-y-auto rounded-2xl border border-n-weak bg-n-background p-0 text-n-slate-12 shadow-xl backdrop:bg-black/50"
    @cancel.prevent="emit('close')"
    @click="if ($event.target === dialog) emit('close');"
  >
    <div class="jrc-service-desk-root block p-4 sm:p-6">
      <header class="mb-4 flex items-center justify-between gap-3">
        <h2 id="sd-archived-tickets-title" class="m-0 text-lg font-semibold">
          {{ t('JRC_SERVICE_DESK.SCREENS.tickets') }} —
          {{ t('JRC_SERVICE_DESK.OPS.KPI.closed') }}
        </h2>
        <Button
          variant="ghost"
          icon="i-lucide-x"
          :label="t('JRC_SERVICE_DESK.COMMON.close')"
          @click="emit('close')"
        />
      </header>
      <TicketTable
        v-if="result.status === 'ready'"
        :items="result.items"
        @open="emit('open', $event)"
        @preview="emit('open', $event)"
      />
      <State v-else :status="result.status" retry @retry="load()" />
      <PaginationFooter
        v-if="result.meta && result.meta.total > 0"
        :current-page="result.meta.page"
        :total-items="result.meta.total"
        :items-per-page="result.meta.per_page"
        @update:current-page="emit('page', $event)"
      />
    </div>
  </dialog>
</template>
