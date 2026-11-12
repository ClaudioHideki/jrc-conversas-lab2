<script setup>
import { ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import CustomerPanel from './CustomerPanel.vue';
import WorkContextPanel from './WorkContextPanel.vue';
import DocumentsPanel from './DocumentsPanel.vue';
import { buttonClass, inputClass, message } from './definitions';
const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const metadata = ref(null);
const rows = ref([]);
const error = ref('');
const loading = ref(false);
const query = ref(String(route.query.q || ''));
const tab = ref('relationship');
const pagination = ref({ page: 1, total: 0, per_page: 25 });
watch(
  [
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    () => route.query.q,
    () => route.query.page,
    () => route.query.customer_segment_id,
  ],
  async (_, __, cleanup) => {
    const controller = new AbortController();
    cleanup(() => controller.abort());
    metadata.value = null;
    rows.value = [];
    error.value = '';
    loading.value = true;
    try {
      const options = { signal: controller.signal };
      const accountId = route.params.accountId;
      const [meta, list] = await Promise.all([
        API.metadata(accountId, options),
        API.portfolio(
          accountId,
          {
            q: route.query.q,
            page: route.query.page || 1,
            customer_segment_id: route.query.customer_segment_id || undefined,
          },
          options
        ),
      ]);
      if (!controller.signal.aborted) {
        metadata.value = meta.data;
        rows.value = list.data.payload;
        pagination.value = list.data.meta;
      }
    } catch (err) {
      if (!controller.signal.aborted) error.value = message(err);
    } finally {
      if (!controller.signal.aborted) loading.value = false;
    }
  },
  { immediate: true }
);
const update = values =>
  router.replace({ query: { ...route.query, ...values } });
</script>

<template>
  <div class="min-h-0 flex-1 space-y-4 overflow-y-auto p-5">
    <h2 class="text-xl font-semibold">
      {{ t('RELATIONSHIP.V2.AREAS.customers') }}
    </h2>
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ error }}
    </p>
    <p
      v-if="loading"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <template v-if="metadata">
      <template v-if="route.query.assignment_id">
        <button
          type="button"
          :class="buttonClass"
          @click="update({ assignment_id: undefined })"
        >
          {{ t('RELATIONSHIP.V2.BACK_TO_LIST') }}
        </button>
        <nav
          class="flex gap-2"
          :aria-label="t('RELATIONSHIP.V2.AREAS.customers')"
        >
          <button
            v-for="key in [
              'relationship',
              'modules',
              ...(metadata.can_view_documents ? ['documents'] : []),
            ]"
            :key="key"
            :class="[
              buttonClass,
              tab === key &&
                'border-violet-500 text-violet-700 dark:text-violet-300',
            ]"
            :aria-pressed="tab === key"
            @click="tab = key"
          >
            {{ t(`RELATIONSHIP.V2.TABS.${key}`) }}
          </button>
        </nav>
        <CustomerPanel
          v-if="tab === 'relationship'"
          :assignment-id="route.query.assignment_id"
          :metadata="metadata"
          @close="update({ assignment_id: undefined })"
        />
        <WorkContextPanel
          v-else-if="tab === 'modules'"
          :assignment-id="route.query.assignment_id"
        />
        <DocumentsPanel
          v-else-if="metadata.can_view_documents"
          :assignment-id="route.query.assignment_id"
          :metadata="metadata"
        />
      </template>
      <template v-else>
        <form
          class="flex gap-3"
          @submit.prevent="update({ q: query, page: 1 })"
        >
          <input
            v-model="query"
            type="search"
            :aria-label="t('RELATIONSHIP.FIELDS.customer')"
            :class="inputClass"
            maxlength="100"
          /><button
            :class="buttonClass"
            type="submit"
          >
            {{ t('RELATIONSHIP.FILTER') }}
          </button>
        </form>
        <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          <button
            v-for="row in rows"
            :key="row.id"
            type="button"
            class="rounded-xl border border-cyan-300 bg-cyan-50 p-5 text-left text-cyan-950 hover:shadow-md dark:border-cyan-800 dark:bg-cyan-950/40 dark:text-cyan-100"
            @click="update({ assignment_id: row.id })"
          >
            <span
              class="i-lucide-building-2 mb-3 block size-7"
              aria-hidden="true"
            /><strong>{{ row.name }}</strong>
            <p class="mt-2 text-sm">
              {{ row.owner?.name || t('RELATIONSHIP.UNAVAILABLE') }}
            </p>
            <p class="mt-2 text-sm">{{ t('RELATIONSHIP.V2.OPEN_360') }}</p>
          </button>
        </div>
        <nav
          class="flex items-center justify-between"
          :aria-label="t('RELATIONSHIP.V2.PAGINATION')"
        >
          <button
            :class="buttonClass"
            :disabled="pagination.page <= 1"
            @click="update({ page: pagination.page - 1 })"
          >
            {{ t('RELATIONSHIP.V2.PREVIOUS') }}</button
          ><span>{{
            t('RELATIONSHIP.V2.PAGE', {
              page: pagination.page,
              total: pagination.total,
            })
          }}</span
          ><button
            :class="buttonClass"
            :disabled="
              pagination.page * pagination.per_page >= pagination.total
            "
            @click="update({ page: pagination.page + 1 })"
          >
            {{ t('RELATIONSHIP.V2.NEXT') }}
          </button>
        </nav>
      </template>
    </template>
  </div>
</template>
