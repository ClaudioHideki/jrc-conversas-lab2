<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { activitiesAPI, followUpsAPI } from 'dashboard/api/crm';
import { formatCrmDateTime } from '../../utils/dateTime';

const props = defineProps({ refreshKey: { type: Number, default: 0 } });
const emit = defineEmits(['changed', 'edit']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const record = ref(null);
const error = ref(false);
const loading = ref(false);
const pendingIdentities = reactive(new Set());
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    authorityScope(store.getters),
    route.query.activityId,
    route.query.followUpId,
  ])
);
const busy = computed(() => pendingIdentities.has(identity.value));
const selectedId = computed(
  () => route.query.followUpId || route.query.activityId
);
const api = computed(() =>
  route.query.followUpId ? followUpsAPI : activitiesAPI
);
const completed = computed(
  () =>
    record.value?.completed_at ||
    record.value?.is_completed ||
    record.value?.status === 'completed'
);
let generation = 0;
let requestGeneration = 0;
let disposed = false;
const captureContext = () => ({ identity: identity.value, generation });
const isCurrent = context =>
  !disposed &&
  context.identity === identity.value &&
  context.generation === generation;
const load = async () => {
  const context = captureContext();
  requestGeneration += 1;
  const request = requestGeneration;
  record.value = null;
  error.value = false;
  loading.value = Boolean(selectedId.value);
  if (!selectedId.value || disposed) return;
  try {
    const { data } = await api.value.show(selectedId.value);
    if (isCurrent(context) && request === requestGeneration)
      record.value = data;
  } catch {
    if (isCurrent(context) && request === requestGeneration) error.value = true;
  } finally {
    if (isCurrent(context) && request === requestGeneration)
      loading.value = false;
  }
};
watch(
  identity,
  () => {
    generation += 1;
    load();
  },
  { immediate: true, flush: 'sync' }
);
watch(() => props.refreshKey, load);
onBeforeUnmount(() => {
  disposed = true;
  generation += 1;
  requestGeneration += 1;
});
const editable = () =>
  !disposed &&
  record.value &&
  !loading.value &&
  !error.value &&
  !busy.value &&
  !completed.value &&
  record.value.status !== 'cancelled';
const edit = () => {
  if (editable() && !route.query.followUpId) emit('edit', record.value.id);
};
async function complete() {
  if (!editable()) return;
  const context = captureContext();
  pendingIdentities.add(context.identity);
  try {
    const { data } = await api.value.complete(selectedId.value);
    if (isCurrent(context)) {
      requestGeneration += 1;
      loading.value = false;
      record.value = data;
      error.value = false;
      emit('changed');
    }
  } catch {
    if (isCurrent(context)) error.value = true;
  } finally {
    pendingIdentities.delete(context.identity);
  }
}
</script>

<template>
  <section
    v-if="selectedId"
    class="rounded-xl border border-n-blue-6 bg-n-solid-1 p-4"
    aria-live="polite"
  >
    <p v-if="loading">{{ t('CRM.AGENDA_RECORD.LOADING') }}</p>
    <p v-else-if="error" role="alert">
      {{ t('CRM.AGENDA_RECORD.UNAVAILABLE') }}
    </p>
    <template v-else-if="record">
      <h2 class="text-lg font-semibold">{{ record.title }}</h2>
      <p class="whitespace-pre-wrap">{{ record.description }}</p>
      <p>{{ formatCrmDateTime(record.due_at) }}</p>
      <button
        v-if="
          !route.query.followUpId && !completed && record.status !== 'cancelled'
        "
        type="button"
        data-testid="agenda-record-edit"
        class="mr-2 mt-3 rounded-lg border border-n-weak px-3 py-2"
        :disabled="busy"
        @click="edit"
      >
        {{ t('CRM.ACTIVITY_EDIT.TITLE') }}
      </button>
      <p v-if="completed">{{ t('CRM.AGENDA_RECORD.COMPLETED') }}</p>
      <button
        v-else-if="record.status !== 'cancelled'"
        class="mt-3 rounded-lg bg-n-blue-9 px-3 py-2 text-white disabled:opacity-50"
        :disabled="busy"
        data-testid="agenda-record-complete"
        @click="complete"
      >
        {{ t('CRM.AGENDA_RECORD.COMPLETE') }}
      </button>
    </template>
  </section>
</template>
