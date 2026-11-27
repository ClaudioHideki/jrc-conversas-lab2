<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcContactCenter';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  recordingId: { type: [String, Number], required: true },
});
const { t } = useI18n();
const labels = computed(() => ({
  TITLE: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.TITLE'),
  NOTICE: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.NOTICE'),
  DATE: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.DATE'),
  ACTOR: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.ACTOR'),
  OPERATION: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.OPERATION'),
  REQUEST: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.REQUEST'),
  EMPTY: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.EMPTY'),
  ERROR: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.ERROR'),
  DENIED: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.DENIED'),
  UNAVAILABLE: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.UNAVAILABLE'),
  UNKNOWN_ACTOR: t(
    'JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.UNKNOWN_ACTOR'
  ),
  UNKNOWN_REQUEST: t(
    'JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.UNKNOWN_REQUEST'
  ),
  LOADING: t('JRC_CONTACT_CENTER.COMMON.LOADING'),
  RETRY: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.RETRY'),
  PREVIOUS: t('JRC_CONTACT_CENTER.ADMIN.PREVIOUS'),
  NEXT: t('JRC_CONTACT_CENTER.ADMIN.NEXT'),
}));
const operations = computed(() => ({
  view: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.VIEW'),
  listen: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.LISTEN'),
  download: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.DOWNLOAD'),
  reproduce: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.REPRODUCE'),
  transcript: t('JRC_CONTACT_CENTER.RECORDINGS.ACCESS_HISTORY.TRANSCRIPT'),
}));
const rows = ref([]);
const loading = ref(false);
const error = ref('');
const timezone = ref('UTC');
const page = ref(1);
const meta = ref({ total: 0, pages: 0 });
let generation = 0;

const load = async targetPage => {
  generation += 1;
  const version = generation;
  const account = String(props.accountId);
  const recording = String(props.recordingId);
  rows.value = [];
  meta.value = { total: 0, pages: 0 };
  loading.value = true;
  page.value = targetPage;
  error.value = '';
  try {
    const response = await API.recordingAccessHistory(account, recording, {
      page: targetPage,
      per_page: 20,
    });
    if (version !== generation) return;
    const data = response.data;
    if (
      String(data.account_id) !== account ||
      String(data.recording_id) !== recording ||
      !Array.isArray(data.items) ||
      typeof data.timezone !== 'string' ||
      !data.timezone ||
      !data.meta ||
      data.meta.page !== targetPage
    )
      throw new Error('Changed native recording history identity');
    const formatter = new Intl.DateTimeFormat('pt-BR', {
      dateStyle: 'short',
      timeStyle: 'medium',
      timeZone: data.timezone,
    });
    rows.value = data.items.map(row => {
      if (
        !operations.value[row.operation] ||
        typeof row.created_at !== 'string' ||
        !row.created_at
      )
        throw new Error('Unknown native recording audit');
      return {
        ...row,
        formattedDate: formatter.format(new Date(row.created_at)),
      };
    });
    timezone.value = data.timezone;
    meta.value = data.meta;
    page.value = targetPage;
  } catch (failure) {
    if (version !== generation) return;
    rows.value = [];
    const status = failure?.response?.status;
    if ([401, 403].includes(status)) error.value = 'DENIED';
    else if (status === 404) error.value = 'UNAVAILABLE';
    else error.value = 'ERROR';
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(
  () => [props.accountId, props.recordingId],
  () => {
    page.value = 1;
    load(1);
  },
  { immediate: true, flush: 'pre' }
);
onBeforeUnmount(() => {
  generation += 1;
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 border-t border-n-weak pt-3"
    data-recording-access-history
  >
    <h3 class="font-semibold">{{ labels.TITLE }}</h3>
    <p class="break-words text-xs text-n-slate-11">{{ labels.NOTICE }}</p>
    <p v-if="loading" role="status">{{ labels.LOADING }}</p>
    <div v-else-if="error" class="space-y-2">
      <p role="alert" class="text-n-ruby-11">{{ labels[error] }}</p>
      <button
        type="button"
        class="rounded border border-n-weak px-3 py-2"
        data-recording-audit-retry
        @click="load(page)"
      >
        {{ labels.RETRY }}
      </button>
    </div>
    <template v-else>
      <p v-if="!rows.length" data-recording-audit-empty>{{ labels.EMPTY }}</p>
      <div
        v-else
        class="max-h-72 min-w-0 overflow-y-auto rounded-lg border border-n-weak"
      >
        <ol class="m-0 list-none divide-y divide-n-weak p-0">
          <li
            v-for="row in rows"
            :key="row.id"
            class="min-w-0 space-y-1 p-3 text-sm"
            :data-recording-audit-row="row.id"
          >
            <dl class="m-0 space-y-1">
              <div class="break-words">
                <dt class="inline font-medium">{{ labels.DATE }}</dt>
                <dd class="ml-2 inline">
                  {{ `${row.formattedDate} (${timezone})` }}
                </dd>
              </div>
              <div class="break-all">
                <dt class="inline font-medium">{{ labels.ACTOR }}</dt>
                <dd class="ml-2 inline">
                  {{ row.actor_id ? `#${row.actor_id}` : labels.UNKNOWN_ACTOR }}
                </dd>
              </div>
              <div>
                <dt class="inline font-medium">{{ labels.OPERATION }}</dt>
                <dd class="ml-2 inline">{{ operations[row.operation] }}</dd>
              </div>
              <div class="break-all text-xs text-n-slate-11">
                <dt class="inline font-medium">{{ labels.REQUEST }}</dt>
                <dd class="ml-2 inline">
                  {{ row.request_id || labels.UNKNOWN_REQUEST }}
                </dd>
              </div>
            </dl>
          </li>
        </ol>
      </div>
      <nav
        v-if="meta.pages > 1 || page > 1"
        class="flex flex-wrap items-center justify-between gap-2"
        :aria-label="labels.TITLE"
      >
        <button
          type="button"
          :disabled="page <= 1"
          class="rounded border border-n-weak px-3 py-2 disabled:opacity-50"
          @click="load(page - 1)"
        >
          {{ labels.PREVIOUS }}
        </button>
        <span>{{ `${page} / ${meta.pages}` }}</span>
        <button
          type="button"
          :disabled="page >= meta.pages"
          class="rounded border border-n-weak px-3 py-2 disabled:opacity-50"
          @click="load(page + 1)"
        >
          {{ labels.NEXT }}
        </button>
      </nav>
    </template>
  </section>
</template>
