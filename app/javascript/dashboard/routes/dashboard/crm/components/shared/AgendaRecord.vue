<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { activitiesAPI, followUpsAPI } from 'dashboard/api/crm';
import { formatCrmDateTime } from '../../utils/dateTime';

const props = defineProps({ refreshKey: { type: Number, default: 0 } });
const emit = defineEmits(['changed', 'edit']);
const route = useRoute();
const { t } = useI18n();
const record = ref(null);
const error = ref(false);
const loading = ref(false);
const busy = ref(false);
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
watch(
  () => [
    route.params.accountId,
    route.query.activityId,
    route.query.followUpId,
    props.refreshKey,
  ],
  async () => {
    generation += 1;
    const version = generation;
    record.value = null;
    error.value = false;
    loading.value = Boolean(selectedId.value);
    if (!selectedId.value) return;
    try {
      const { data } = await api.value.show(selectedId.value);
      if (version === generation) record.value = data;
    } catch {
      if (version === generation) error.value = true;
    } finally {
      if (version === generation) loading.value = false;
    }
  },
  { immediate: true }
);

async function complete() {
  const version = generation;
  busy.value = true;
  try {
    const { data } = await api.value.complete(selectedId.value);
    if (version === generation) {
      record.value = data;
      emit('changed');
    }
  } catch {
    if (version === generation) error.value = true;
  } finally {
    busy.value = false;
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
        @click="emit('edit', record.id)"
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
