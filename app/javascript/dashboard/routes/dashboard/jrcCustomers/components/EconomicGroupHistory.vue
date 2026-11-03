<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcCustomers';
import { useCustomerMaster } from '../useCustomerMaster';
import { T, buttonClass, errorMessage } from '../copy';

const props = defineProps({
  groupId: { type: [Number, String], required: true },
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
    const { data } = await API.economicGroupRecords(
      props.groupId,
      'history',
      { page: page.value },
      { accountId: accountId.value, signal: controller.signal }
    );
    if (token !== generation) return;
    rows.value = data.payload;
    meta.value = data.meta;
  } catch (failure) {
    if (token === generation) error.value = errorMessage(failure);
  } finally {
    if (token === generation) busy.value = false;
  }
};
watch(
  [identity, () => props.groupId],
  () => {
    if (page.value !== 1) page.value = 1;
    else load();
  },
  { immediate: true }
);
watch(page, load);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
const eventLabel = kind =>
  ({
    customer_economic_group_created: t('CRM.ECONOMIC_GROUPS.CREATED'),
    customer_economic_group_updated: t('CRM.ECONOMIC_GROUPS.UPDATED'),
    customer_economic_group_linked: t('CRM.ECONOMIC_GROUPS.MEMBERSHIP_CHANGED'),
  })[kind] || t('CRM.ECONOMIC_GROUPS.UPDATED');
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
      class="rounded-lg border border-n-weak bg-n-solid-2 p-3"
    >
      <strong>{{ eventLabel(row.kind) }}</strong>
      <p>
        {{ row.actor_name || t('CRM.CORPORATE_SEGMENTS.SYSTEM') }} ·
        {{ date(row.at) }}
      </p>
    </article>
    <p v-if="!busy && !rows.length">{{ T.noResults }}</p>
    <div class="flex items-center gap-3">
      <button
        type="button"
        :class="buttonClass"
        :disabled="busy || page <= 1"
        @click="page -= 1"
      >
        {{ T.previous }}
      </button>
      <span>{{
        `${page} / ${Math.max(1, Math.ceil(meta.total / meta.per_page))}`
      }}</span>
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
