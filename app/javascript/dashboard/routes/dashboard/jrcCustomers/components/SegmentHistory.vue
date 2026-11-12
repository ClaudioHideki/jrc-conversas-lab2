<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, buttonClass, errorMessage } from '../copy';
const props = defineProps({
  taxonomyId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const { accountId, identity, date } = useCustomerMaster();
const rows = ref([]);
const page = ref(1);
const meta = ref({ total: 0, per_page: 25 });
const error = ref('');
const busy = ref(false);
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  busy.value = true;
  error.value = '';
  try {
    const result = await API.segmentRecords(
      props.taxonomyId,
      'history',
      { page: page.value },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (token !== generation) return;
    rows.value = result.data.payload;
    meta.value = result.data.meta;
  } catch (failure) {
    if (token === generation) error.value = errorMessage(failure);
  } finally {
    if (token === generation) busy.value = false;
  }
};
watch(
  [identity, () => props.taxonomyId],
  () => {
    page.value = 1;
    load();
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="space-y-3">
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      role="status"
    >
      {{ T.loading }}
    </p>
    <article
      v-for="row in rows"
      :key="row.id"
      class="rounded-lg border border-n-weak p-3"
    >
      <strong>{{
        row.kind === 'customer_segment_created'
          ? t('CRM.CORPORATE_SEGMENTS.CREATED')
          : row.kind === 'customer_segment_override_changed'
            ? t('CRM.CORPORATE_SEGMENTS.CHOICE_CHANGED')
            : t('CRM.CORPORATE_SEGMENTS.UPDATED')
      }}</strong>
      <p>
        {{ row.actor_name || t('CRM.CORPORATE_SEGMENTS.SYSTEM') }} ·
        {{ date(row.at) }}
      </p>
    </article>
    <p v-if="!busy && !rows.length">{{ T.noResults }}</p>
    <div class="flex gap-3">
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="page -= 1"
      >
        {{ T.previous }}
      </button>
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page * meta.per_page >= meta.total"
        @click="page += 1"
      >
        {{ T.next }}
      </button>
    </div>
  </section>
</template>
