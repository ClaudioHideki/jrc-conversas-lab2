<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import API from 'dashboard/api/jrcRelationship';
import DistributionCapacitySummary from './DistributionCapacitySummary.vue';
import { buttonClass } from './definitions';
const props = defineProps({ analystId: { type: Number, required: true } });
const emit = defineEmits(['close']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const record = ref(null);
const busy = ref(false);
const error = ref(false);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.analystId,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
  ])
);
let generation = 0;
let controller;
const clear = () => {
  generation += 1;
  controller?.abort();
  record.value = null;
  busy.value = false;
};
const load = async (page = 1) => {
  clear();
  const token = generation;
  controller = new AbortController();
  busy.value = true;
  error.value = false;
  try {
    const { data } = await API.analystCapacity(
      route.params.accountId,
      props.analystId,
      { page, per_page: 10 },
      { signal: controller.signal }
    );
    if (token !== generation) return;
    if (data.analyst.id !== props.analystId)
      throw new Error('Invalid capacity identity');
    record.value = data;
  } catch {
    if (token === generation) error.value = true;
  } finally {
    if (token === generation) busy.value = false;
  }
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
    width="xl"
    :title="t('RELATIONSHIP.CAPACITY.CURRENT_TITLE')"
    :show-confirm-button="false"
    :use-form="false"
    show-close-button
    @close="emit('close')"
  >
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ t('RELATIONSHIP.CAPACITY.CURRENT_UNAVAILABLE') }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <section
      v-if="record"
      class="min-w-0"
    >
      <h3 class="font-semibold">{{ record.analyst.name }}</h3>
      <p
        v-if="!record.analyst.active_user"
        role="status"
        class="text-sm text-n-amber-11"
      >
        {{ t('RELATIONSHIP.CAPACITY.CURRENT_INACTIVE') }}
      </p>
      <DistributionCapacitySummary
        :rows="record.payload"
        current-only
      />
      <p
        v-if="!record.payload.length"
        role="status"
      >
        {{ t('RELATIONSHIP.CAPACITY.CURRENT_EMPTY') }}
      </p>
      <div class="mt-3 flex flex-wrap gap-3">
        <button
          type="button"
          data-testid="capacity-previous"
          :class="buttonClass"
          :disabled="busy || record.meta.page <= 1"
          @click="load(record.meta.page - 1)"
        >
          {{ t('RELATIONSHIP.HEALTH_PREVIEW.PREVIOUS') }}
        </button>
        <span>{{
          t('RELATIONSHIP.CAPACITY.CURRENT_PAGE', {
            page: record.meta.page,
            total: record.meta.total,
          })
        }}</span>
        <button
          type="button"
          data-testid="capacity-next"
          :class="buttonClass"
          :disabled="
            busy || record.meta.page * record.meta.per_page >= record.meta.total
          "
          @click="load(record.meta.page + 1)"
        >
          {{ t('RELATIONSHIP.HEALTH_PREVIEW.NEXT') }}
        </button>
      </div>
    </section>
  </Dialog>
</template>
