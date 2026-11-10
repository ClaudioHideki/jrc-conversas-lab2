<script setup>
import { computed, ref, watch, onMounted, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import MetricDrilldownPanel from './MetricDrilldownPanel.vue';
import { buttonClass, message } from './definitions';
const props = defineProps({
  metric: { type: String, required: true },
  filters: { type: Object, default: () => ({}) },
  metadata: { type: Object, default: () => ({}) },
});
const emit = defineEmits(['close', 'invalidated']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const data = ref(null);
const error = ref('');
const busy = ref(false);
const page = ref(1);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser,
    props.metric,
    props.filters,
  ])
);
let generation = 0;
let controller;
const clear = () => {
  generation += 1;
  controller?.abort();
  data.value = null;
  error.value = '';
};
const load = async (recoverPage = true) => {
  clear();
  const token = generation;
  controller = new AbortController();
  busy.value = true;
  try {
    const result = await API.drilldown(
      route.params.accountId,
      { ...props.filters, metric: props.metric, page: page.value },
      { signal: controller.signal }
    );
    if (token !== generation) return;
    const last = Math.max(
      1,
      Math.ceil(result.data.total / result.data.per_page)
    );
    if (recoverPage && page.value > last) {
      page.value = last;
      await load(false);
      return;
    }
    data.value = result.data;
  } catch (failure) {
    if (token !== generation) return;
    error.value = message(failure);
    if ([403, 404].includes(failure.response?.status)) emit('invalidated');
  } finally {
    if (token === generation) busy.value = false;
  }
};
const changePage = value => {
  if (busy.value) return;
  page.value = value;
  load();
};
watch(identity, () => {
  clear();
  emit('close');
});
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(clear);
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t(`RELATIONSHIP.METRICS.${metric}`)"
    :description="t('RELATIONSHIP.DRILLDOWN_DIALOG.NOTE')"
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    show-close-button
    width="2xl"
    @close="emit('close')"
  >
    <div class="min-w-0 space-y-3">
      <p
        v-if="busy"
        role="status"
      >
        {{ t('RELATIONSHIP.LOADING') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="break-words text-n-ruby-11"
      >
        {{ error }}
      </p>
      <MetricDrilldownPanel
        v-if="data && data.value !== null"
        :data="data"
        :metadata="metadata"
        @close="emit('close')"
        @page="changePage"
      />
      <p
        v-else-if="data"
        role="status"
      >
        {{ t('RELATIONSHIP.UNAVAILABLE') }}
      </p>
      <button
        v-if="error"
        type="button"
        :class="buttonClass"
        :disabled="busy"
        @click="() => load()"
      >
        {{ t('RELATIONSHIP.DRILLDOWN_DIALOG.RETRY') }}
      </button>
    </div>
  </Dialog>
</template>
