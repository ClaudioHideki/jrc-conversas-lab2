<script setup>
import { accountMembershipAccess } from 'dashboard/helper/accountMembershipAccess';
import { computed, ref, watch, onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, message, date as formatDate } from './definitions';
const props = defineProps({
  allowed: Boolean,
  book: { type: Object, default: null },
  formatting: { type: Object, default: () => ({}) },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const rows = ref([]);
const error = ref('');
const loading = ref(false);
const denied = ref(false);
const page = ref(0);
const cursors = ref([null]);
const nextCursor = ref(null);
const currentOnly = ref(false);
const bookId = computed(() => (currentOnly.value ? props.book?.id : null));
const attempt = ref({ cursor: null, page: 0 });
let generation = 0;
let controller;
const reset = () => {
  generation += 1;
  controller?.abort();
  rows.value = [];
  error.value = '';
  loading.value = false;
  denied.value = false;
  page.value = 0;
  cursors.value = [null];
  nextCursor.value = null;
  attempt.value = { cursor: null, page: 0 };
};
const load = async (cursor = null, target = 0) => {
  if (!props.allowed || loading.value || denied.value) return;
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  rows.value = [];
  nextCursor.value = null;
  error.value = '';
  loading.value = true;
  attempt.value = { cursor, page: target };
  try {
    const { data } = await API.playbookExecutions(route.params.accountId, {
      params: {
        per_page: 25,
        ...(cursor ? { before_id: cursor } : {}),
        ...(bookId.value ? { playbook_id: bookId.value } : {}),
      },
      signal: controller.signal,
    });
    if (version !== generation) return;
    const next = data.meta?.next_before_id;
    if (
      !Array.isArray(data.payload) ||
      data.payload.length > 25 ||
      data.payload.some(
        (row, index) =>
          !Number.isSafeInteger(row.id) ||
          row.id < 1 ||
          (cursor && row.id >= cursor) ||
          (index > 0 && data.payload[index - 1].id <= row.id)
      ) ||
      data.meta?.per_page !== 25 ||
      (next !== null &&
        (!Number.isSafeInteger(next) ||
          next < 1 ||
          next !== data.payload.at(-1)?.id ||
          (cursor && next >= cursor)))
    )
      throw new Error(t('RELATIONSHIP.EXECUTION_HISTORY.UNCONFIRMED'));
    rows.value = data.payload;
    nextCursor.value = next;
    cursors.value = [...cursors.value.slice(0, target), cursor];
    page.value = target;
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED') {
      error.value = message(err);
      denied.value = [401, 403].includes(err.response?.status);
    }
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => store.getters.getCurrentRole,
    () =>
      JSON.stringify(
        store.getters.getCurrentUser?.accounts?.map(accountMembershipAccess)
      ),
    () => props.allowed,
    bookId,
  ],
  () => {
    reset();
    if (props.allowed) load();
  },
  { immediate: true }
);
watch(
  () => props.book?.id,
  value => {
    if (!value) currentOnly.value = false;
  }
);
onBeforeUnmount(reset);
</script>

<template>
  <section class="mt-4 min-w-0 space-y-3">
    <h3>{{ t('RELATIONSHIP.PLAYBOOK_EXECUTIONS') }}</h3>
    <label
      v-if="allowed && book && !denied"
      class="flex items-start gap-2 text-sm"
    >
      <input
        v-model="currentOnly"
        type="checkbox"
        :disabled="loading"
        data-test="execution-current-book"
      />
      {{
        t('RELATIONSHIP.EXECUTION_HISTORY.CURRENT_BOOK', { name: book.name })
      }}
    </label>
    <p
      v-if="loading"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
    >
      {{ error }}
    </p>
    <details
      v-for="row in rows"
      :key="row.id"
      class="min-w-0 break-words rounded-lg border border-n-weak p-3"
    >
      <summary>
        {{ row.customer_name }} · {{ row.snapshot.name }} ·
        {{ t('RELATIONSHIP.VERSION', { version: row.version }) }} ·
        {{ formatDate(row.created_at, formatting) }}
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
          >
            {{ t('RELATIONSHIP.NEW_ACTIVITY') }}
          </RouterLink>
        </li>
      </ul>
    </details>
    <p v-if="!rows.length && !error && !loading">
      {{ t('RELATIONSHIP.EMPTY') }}
    </p>
    <nav
      v-if="allowed && !denied"
      class="flex flex-wrap items-center gap-2"
      :aria-label="t('RELATIONSHIP.EXECUTION_HISTORY.NAVIGATION')"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading || page === 0"
        data-test="execution-previous"
        @click="load(cursors[page - 1], page - 1)"
      >
        {{ t('RELATIONSHIP.EXECUTION_HISTORY.PREVIOUS') }}
      </button>
      <span>{{
        t('RELATIONSHIP.EXECUTION_HISTORY.PAGE', { page: page + 1 })
      }}</span>
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading || !nextCursor"
        data-test="execution-next"
        @click="load(nextCursor, page + 1)"
      >
        {{ t('RELATIONSHIP.EXECUTION_HISTORY.NEXT') }}
      </button>
      <button
        type="button"
        :class="buttonClass"
        :disabled="loading"
        data-test="execution-reload"
        @click="load(attempt.cursor, attempt.page)"
      >
        {{ t('RELATIONSHIP.EXECUTION_HISTORY.RELOAD') }}
      </button>
    </nav>
  </section>
</template>
