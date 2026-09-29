<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { lostReasonsAPI } from 'dashboard/api/crm';
import KanbanColumn from './KanbanColumn.vue';
import KanbanFilters from './KanbanFilters.vue';
import { useDragAndDrop } from '../../composables/useDragAndDrop';
import CrmPageHeader from '../shared/CrmPageHeader.vue';
import CrmValueDisplay from '../shared/CrmValueDisplay.vue';

const store = useStore();
const { t } = useI18n();
const lostReasons = ref([]);
const pendingLostMove = ref(null);
const lostReasonId = ref('');
const initializing = ref(true);
const actionError = ref(null);

// Filters state
const filters = ref({
  pipeline_id: null,
  owner_id: null,
  search: '',
});

const loadKanbanData = async () => {
  await store.dispatch('jrcCrm/deals/fetchKanbanData', filters.value);
};

// Load initial data
const initialize = async () => {
  initializing.value = true;
  try {
    await store.dispatch('jrcCrm/pipelines/fetchPipelines');
    if (store.getters['jrcCrm/pipelines/error']) return;
    filters.value.pipeline_id =
      store.getters['jrcCrm/pipelines/allPipelines'][0]?.id || null;
    await loadKanbanData();
  } finally {
    initializing.value = false;
  }
};
onMounted(() => {
  store.dispatch('agents/get');
  initialize();
});

// Columns = stages from selected pipeline
const columns = computed(() => {
  return store.getters['jrcCrm/deals/dealsByStage'] || [];
});
const loading = computed(
  () => initializing.value || store.getters['jrcCrm/deals/isLoading']
);
const error = computed(
  () =>
    store.getters['jrcCrm/pipelines/error'] ||
    store.getters['jrcCrm/deals/error']
);
const hasPipelines = computed(
  () => store.getters['jrcCrm/pipelines/allPipelines'].length > 0
);
const dealCount = computed(() =>
  columns.value.reduce((total, column) => total + column.deals.length, 0)
);
const pipelineValue = computed(() =>
  columns.value.reduce(
    (total, column) =>
      total +
      column.deals.reduce(
        (columnTotal, deal) => columnTotal + Number(deal.value_cents || 0),
        0
      ),
    0
  )
);

const performMove = async ({ dealId, fromStageId, toStageId, reasonId }) => {
  actionError.value = null;
  store.commit('jrcCrm/deals/UPDATE_DEAL_STAGE', {
    dealId,
    stageId: toStageId,
  });
  try {
    await store.dispatch('jrcCrm/deals/moveStage', {
      dealId,
      stageId: toStageId,
      lostReasonId: reasonId,
    });
    await loadKanbanData();
  } catch {
    actionError.value = t('CRM.FUNNEL.MOVE_ERROR');
    store.commit('jrcCrm/deals/ROLLBACK_DEAL_STAGE', {
      dealId,
      stageId: fromStageId,
    });
  }
};

const confirmLostMove = async () => {
  await performMove({ ...pendingLostMove.value, reasonId: lostReasonId.value });
  pendingLostMove.value = null;
  lostReasonId.value = '';
};

// Drag and drop
const { onDragStart, onDragOver, onDrop, onDragEnd } = useDragAndDrop({
  onMove: async ({ dealId, fromStageId, toStageId }) => {
    const targetStage = columns.value.find(
      column => Number(column.stage.id) === Number(toStageId)
    )?.stage;
    if (targetStage?.is_lost) {
      try {
        const { data } = await lostReasonsAPI.list();
        lostReasons.value = data;
      } catch {
        actionError.value = t('CRM.FUNNEL.REASONS_ERROR');
        return;
      }
      pendingLostMove.value = {
        dealId,
        fromStageId,
        toStageId,
      };
      return;
    }
    await performMove({ dealId, fromStageId, toStageId });
  },
});
</script>

<template>
  <div class="flex h-full min-h-[420px] flex-col overflow-auto bg-n-surface-1">
    <div class="shrink-0 space-y-5 p-4 pb-0 sm:p-6 sm:pb-0">
      <CrmPageHeader
        eyebrow="Pipeline comercial"
        title="Funil de oportunidades"
        description="Arraste os cards entre as etapas para atualizar o andamento."
        icon="i-lucide-columns-3"
        tone="iris"
      >
        <template #meta>
          <span
            class="inline-flex rounded-full bg-n-iris-3 px-3 py-1 text-xs font-semibold text-n-iris-11"
            >Funil comercial</span
          >
          <span
            class="inline-flex items-center gap-1 rounded-full bg-n-blue-3 px-3 py-1 text-xs font-semibold text-n-blue-11"
          >
            <i class="i-lucide-chart-no-axes-column-increasing size-3" />
            {{ dealCount }} oportunidades
          </span>
          <span
            class="inline-flex items-center gap-1 rounded-full bg-n-teal-3 px-3 py-1 text-xs font-semibold text-n-teal-11"
          >
            <i class="i-lucide-circle-dollar-sign size-3" />
            <CrmValueDisplay :cents="pipelineValue" /> no pipeline
          </span>
        </template>
        <template #actions>
          <RouterLink
            :to="{ name: 'crm_deals', query: { new: '1' } }"
            class="rounded-xl bg-n-teal-9 px-4 py-2.5 text-sm font-semibold text-white shadow-md"
          >
            <i
              class="i-lucide-plus mr-1 inline-block h-4 w-4 align-text-bottom"
            />
            Nova oportunidade
          </RouterLink>
        </template>
      </CrmPageHeader>
      <div
        class="overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <KanbanFilters v-model:filters="filters" @change="loadKanbanData" />
      </div>
    </div>
    <div
      v-if="loading"
      class="m-6 rounded-2xl border border-n-weak bg-n-solid-2 p-8 text-center text-n-slate-10 shadow-sm"
    >
      Carregando funil…
    </div>
    <div
      v-else-if="error"
      role="alert"
      class="m-6 rounded-2xl border border-n-ruby-6 bg-n-ruby-3 p-8 text-center text-n-ruby-11"
    >
      {{ error }}
      <button type="button" class="ml-3 underline" @click="initialize">
        {{ t('CRM.FUNNEL.RETRY') }}
      </button>
    </div>
    <div
      v-else-if="!columns.length"
      role="status"
      class="m-6 rounded-2xl border border-n-weak bg-n-solid-2 p-8 text-center text-n-slate-11"
    >
      {{
        hasPipelines ? t('CRM.FUNNEL.NO_STAGES') : t('CRM.FUNNEL.NO_PIPELINES')
      }}
    </div>
    <p
      v-else-if="!dealCount"
      role="status"
      class="mx-6 mt-4 text-sm text-n-slate-11"
    >
      {{ t('CRM.FUNNEL.NO_DEALS') }}
    </p>
    <p v-if="actionError" role="alert" class="mx-6 mt-4 text-sm text-n-ruby-11">
      {{ actionError }}
    </p>
    <div
      v-if="!loading && !error && columns.length"
      class="flex min-h-[300px] flex-1 gap-4 overflow-x-auto p-4 sm:p-6"
    >
      <KanbanColumn
        v-for="column in columns"
        :key="column.stage.id"
        :stage="column.stage"
        :deals="column.deals"
        @drag-start="onDragStart"
        @drag-end="onDragEnd"
        @drag-over="onDragOver"
        @drop="onDrop($event, column.stage.id)"
      />
    </div>
    <Teleport to="body">
      <div
        v-if="pendingLostMove"
        class="fixed inset-0 z-[80] flex items-center justify-center bg-black/40 p-4"
      >
        <div class="w-full max-w-md rounded-xl bg-n-solid-2 p-6 shadow-2xl">
          <h3 class="text-lg font-semibold text-n-slate-12">
            {{ t('CRM.LOSS.TITLE') }}
          </h3>
          <select
            v-model="lostReasonId"
            class="mt-4 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
          >
            <option disabled value="">{{ t('CRM.LOSS.SELECT') }}</option>
            <option
              v-for="reason in lostReasons"
              :key="reason.id"
              :value="reason.id"
            >
              {{ reason.name }}
            </option>
          </select>
          <div class="mt-5 flex justify-end gap-2">
            <button
              type="button"
              class="px-4 py-2 text-sm"
              @click="pendingLostMove = null"
            >
              {{ t('CRM.CANCEL') }}
            </button>
            <button
              type="button"
              :disabled="!lostReasonId"
              class="rounded-lg bg-n-ruby-9 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
              @click="confirmLostMove"
            >
              {{ t('CRM.LOSS.CONFIRM') }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
