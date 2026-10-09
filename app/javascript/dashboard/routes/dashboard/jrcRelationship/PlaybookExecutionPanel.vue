<script setup>
import { ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { message, date as formatDate } from './definitions';
const props = defineProps({ allowed: Boolean });
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const rows = ref([]);
const error = ref('');
let generation = 0;
let controller;
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => props.allowed,
  ],
  async () => {
    generation += 1;
    const version = generation;
    controller?.abort();
    controller = new AbortController();
    rows.value = [];
    error.value = '';
    if (!props.allowed) return;
    try {
      const { data } = await API.playbookExecutions(route.params.accountId, {
        signal: controller.signal,
      });
      if (version === generation) rows.value = data.payload;
    } catch (err) {
      if (version === generation && err.code !== 'ERR_CANCELED')
        error.value = message(err);
    }
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="mt-4 space-y-3">
    <h3>{{ t('RELATIONSHIP.PLAYBOOK_EXECUTIONS') }}</h3>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <details
      v-for="row in rows"
      :key="row.id"
      class="rounded-lg border border-n-weak p-3"
    >
      <summary>
        {{ row.customer_name }} · {{ row.snapshot.name }} ·
        {{ t('RELATIONSHIP.VERSION', { version: row.version }) }} ·
        {{ formatDate(row.created_at) }}
      </summary>
      <p>{{ t('RELATIONSHIP.PLAYBOOK_PLANNED_GUIDANCE') }}</p>
      <ul>
        <li
          v-for="(step, index) in row.snapshot.results || []"
          :key="step.step_key"
        >
          {{ row.snapshot.steps?.[index]?.title }} ·
          {{ t(`RELATIONSHIP.STATES.${step.state}`)
          }}<RouterLink
            v-if="step.activity_id"
            class="ml-2 text-n-brand underline"
            :to="{
              name: 'crm_activities',
              params: { accountId: route.params.accountId },
              query: { activityId: step.activity_id },
            }"
            >{{ t('RELATIONSHIP.NEW_ACTIVITY') }}</RouterLink
          >
        </li>
      </ul>
    </details>
    <p v-if="!rows.length && !error">{{ t('RELATIONSHIP.EMPTY') }}</p>
  </section>
</template>
