<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import DocumentUploadDialog from './DocumentUploadDialog.vue';
import { buttonClass, date as formatDate, message } from './definitions';
const props = defineProps({
  assignmentId: { type: [Number, String], required: true },
  metadata: { type: Object, required: true },
});
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const rows = ref([]);
const page = ref(1);
const meta = ref(null);
const editing = ref(false);
const current = ref(null);
const details = ref(null);
const busy = ref(false);
const error = ref('');
const clearDeniedData = err => {
  if (![403, 404].includes(err.response?.status)) return;
  rows.value = [];
  details.value = null;
  current.value = null;
  editing.value = false;
};
let generation = 0;
let controller;
const load = async () => {
  generation += 1;
  const version = generation;
  controller?.abort();
  controller = new AbortController();
  error.value = '';
  rows.value = [];
  details.value = null;
  busy.value = true;
  try {
    const result = await API.documents(
      route.params.accountId,
      { assignment_id: props.assignmentId, page: page.value },
      { signal: controller.signal }
    );
    if (version === generation) {
      rows.value = result.data.payload;
      meta.value = result.data.meta;
    }
  } catch (err) {
    if (version === generation && err.code !== 'ERR_CANCELED')
      error.value = message(err);
    if (version === generation) clearDeniedData(err);
  } finally {
    if (version === generation) busy.value = false;
  }
};
watch(
  [
    () => props.assignmentId,
    () => route.params.accountId,
    () => store.getters.getCurrentUserID,
    page,
  ],
  () => {
    editing.value = false;
    current.value = null;
    details.value = null;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
const upload = async fields => {
  const version = generation;
  const accountId = route.params.accountId;
  busy.value = true;
  error.value = '';
  const form = new FormData();
  form.append('assignment_id', props.assignmentId);
  form.append('file', fields.file);
  ['title', 'category', 'valid_until', 'change_reason'].forEach(key =>
    form.append(`document[${key}]`, fields[key])
  );
  try {
    await API.uploadDocument(accountId, form, current.value?.id);
    if (version === generation) {
      editing.value = false;
      details.value = null;
      await load();
    }
  } catch (err) {
    if (version === generation) {
      error.value = message(err);
      clearDeniedData(err);
    }
  } finally {
    if (version === generation) busy.value = false;
  }
};
const versions = async (document, pageNumber = 1) => {
  const version = generation;
  error.value = '';
  try {
    const result = await API.document(route.params.accountId, document.id, {
      page: pageNumber,
    });
    if (version === generation) details.value = result.data;
  } catch (err) {
    if (version === generation) {
      error.value = message(err);
      clearDeniedData(err);
    }
  }
};
const download = async (document, version) => {
  error.value = '';
  const identity = generation;
  try {
    const response = await API.downloadDocument(
      route.params.accountId,
      document.id,
      version.id
    );
    if (identity !== generation) return;
    const url = URL.createObjectURL(response.data);
    const anchor = window.document.createElement('a');
    anchor.href = url;
    anchor.download = version.filename;
    anchor.click();
    URL.revokeObjectURL(url);
  } catch (err) {
    if (identity === generation) {
      error.value = message(err);
      clearDeniedData(err);
    }
  }
};
const date = value => formatDate(value, props.metadata.formatting);
</script>

<template>
  <section
    class="space-y-4 rounded-xl border border-n-violet-6 bg-n-solid-2 p-5"
  >
    <header class="flex flex-wrap items-center justify-between gap-3">
      <h3 class="text-lg font-semibold">
        {{ t('RELATIONSHIP.V2.DOCS.HEADING') }}
      </h3>
      <div class="flex gap-2">
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="load"
        >
          {{ t('RELATIONSHIP.REFRESH') }}</button
        ><button
          v-if="metadata.can_manage_documents"
          type="button"
          class="rounded-lg bg-n-violet-9 px-4 py-2 font-semibold text-white"
          :disabled="busy"
          @click="
            current = null;
            editing = true;
          "
        >
          {{ t('RELATIONSHIP.V2.DOCS.UPLOAD') }}
        </button>
      </div>
    </header>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.V2.DOCS.QUARANTINE') }}
    </p>
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
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <article
      v-for="document in rows"
      :key="document.id"
      class="rounded-xl border border-n-weak p-4"
    >
      <div class="flex flex-wrap justify-between gap-2">
        <div>
          <strong>{{ document.title }}</strong>
          <p class="text-sm text-n-slate-11">
            {{ t(`RELATIONSHIP.V2.DOCS.CATEGORIES.${document.category}`) }}
          </p>
          <p class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.V2.DOCS.STATUS') }}:
            {{ t(`RELATIONSHIP.V2.DOCS.STATUSES.${document.status}`) }}
          </p>
          <p class="text-sm text-n-slate-11">
            {{ t('RELATIONSHIP.V2.DOCS.PORTFOLIO_OWNER') }}:
            {{
              document.portfolio_owner?.name ||
              t('RELATIONSHIP.V2.DOCS.UNASSIGNED')
            }}
          </p>
        </div>
        <div class="flex gap-2">
          <button
            type="button"
            :class="buttonClass"
            @click="versions(document)"
          >
            {{ t('RELATIONSHIP.V2.DOCS.VERSIONS') }}</button
          ><button
            v-if="metadata.can_manage_documents"
            type="button"
            :class="buttonClass"
            @click="
              current = document;
              editing = true;
            "
          >
            {{ t('RELATIONSHIP.V2.DOCS.NEW_VERSION') }}
          </button>
        </div>
      </div>
      <div
        v-for="version in document.versions"
        :key="version.id"
        class="mt-3 flex flex-wrap items-center gap-3 text-sm"
      >
        <span
          >{{ t('RELATIONSHIP.VERSION', { version: version.number }) }} ·
          {{ version.filename }}</span
        ><span
          >{{ t('RELATIONSHIP.V2.DOCS.UPLOADED_BY') }}:
          {{
            version.uploaded_by?.name || t('RELATIONSHIP.V2.DOCS.UNAVAILABLE')
          }}
          · {{ date(version.uploaded_at) }}</span
        ><span
          class="rounded-md border px-2 py-1"
          :class="
            version.download_available
              ? 'border-teal-400 text-teal-700 dark:text-teal-300'
              : 'border-amber-400 text-amber-800 dark:text-amber-200'
          "
          >{{ t(`RELATIONSHIP.V2.DOCS.SCAN.${version.scan_state}`) }}</span
        ><span
          v-if="version.expired"
          class="font-semibold text-n-ruby-11"
          >{{ t('RELATIONSHIP.V2.DOCS.EXPIRED') }}</span
        ><span
          >{{ t('RELATIONSHIP.V2.DOCS.VALID_UNTIL') }}:
          {{ date(version.valid_until) }}</span
        ><button
          type="button"
          :class="buttonClass"
          :disabled="!version.download_available"
          @click="download(document, version)"
        >
          {{ t('RELATIONSHIP.V2.DOCS.DOWNLOAD') }}
        </button>
      </div>
    </article>
    <p v-if="!rows.length && !busy">{{ t('RELATIONSHIP.V2.DOCS.EMPTY') }}</p>
    <nav
      v-if="meta"
      class="flex items-center justify-between"
      :aria-label="t('RELATIONSHIP.V2.PAGINATION')"
    >
      <button
        type="button"
        :class="buttonClass"
        :disabled="page <= 1 || busy"
        @click="page -= 1"
      >
        {{ t('RELATIONSHIP.V2.PREVIOUS') }}</button
      ><span>{{ t('RELATIONSHIP.V2.PAGE', { page, total: meta.total }) }}</span
      ><button
        type="button"
        :class="buttonClass"
        :disabled="page * meta.per_page >= meta.total || busy"
        @click="page += 1"
      >
        {{ t('RELATIONSHIP.V2.NEXT') }}
      </button>
    </nav>
    <section
      v-if="details"
      class="space-y-3 rounded-xl border border-blue-300 p-4 dark:border-blue-800"
    >
      <div class="flex justify-between gap-3">
        <h4 class="font-semibold">
          {{ details.title }} · {{ t('RELATIONSHIP.V2.DOCS.VERSIONS') }}
        </h4>
        <button
          type="button"
          :class="buttonClass"
          @click="details = null"
        >
          {{ t('RELATIONSHIP.CLOSE') }}
        </button>
      </div>
      <article
        v-for="version in details.versions"
        :key="version.id"
        class="space-y-2 border-t border-n-weak py-3 text-sm"
      >
        <strong
          >{{ t('RELATIONSHIP.VERSION', { version: version.number }) }} ·
          {{ version.filename }}</strong
        >
        <p>{{ version.change_reason }} · {{ date(version.uploaded_at) }}</p>
        <p>
          {{ t('RELATIONSHIP.V2.DOCS.UPLOADED_BY') }}:
          {{
            version.uploaded_by?.name || t('RELATIONSHIP.V2.DOCS.UNAVAILABLE')
          }}
        </p>
        <p>
          {{ t('RELATIONSHIP.V2.DOCS.VALID_UNTIL') }}:
          {{ date(version.valid_until) }}
          <span
            v-if="version.expired"
            class="text-n-ruby-11"
            >{{ t('RELATIONSHIP.V2.DOCS.EXPIRED') }}</span
          >
        </p>
        <p>{{ t(`RELATIONSHIP.V2.DOCS.SCAN.${version.scan_state}`) }}</p>
        <button
          type="button"
          :class="buttonClass"
          :disabled="!version.download_available"
          @click="download(details, version)"
        >
          {{ t('RELATIONSHIP.V2.DOCS.DOWNLOAD') }}
        </button>
      </article>
      <nav
        v-if="details.versions_meta"
        class="flex justify-between"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="details.versions_meta.page <= 1"
          @click="versions(details, details.versions_meta.page - 1)"
        >
          {{ t('RELATIONSHIP.V2.PREVIOUS') }}</button
        ><button
          type="button"
          :class="buttonClass"
          :disabled="
            details.versions_meta.page * details.versions_meta.per_page >=
            details.versions_meta.total
          "
          @click="versions(details, details.versions_meta.page + 1)"
        >
          {{ t('RELATIONSHIP.V2.NEXT') }}
        </button>
      </nav>
    </section>
    <DocumentUploadDialog
      v-if="editing"
      :document="current"
      :busy="busy"
      :error="error"
      @close="editing = false"
      @save="upload"
    />
  </section>
</template>
