<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';
const props = defineProps({ record: { type: Object, required: true } });
const emit = defineEmits(['changed']);
const store = useStore();
const identity = computed(() =>
  JSON.stringify([authorityScope(store.getters), props.record.id])
);
const { text, date } = useBackofficePresentation();
const result = ref(null);
const selected = ref('');
const page = ref(1);
const view = ref('current');
const visibleVersions = computed(() =>
  (result.value?.data || []).filter(
    version => view.value === 'history' || version.current
  )
);
const file = ref(null);
const fileInput = ref(null);
const reason = ref('');
const expiration = ref('');
const expirationChanged = ref(false);
const busy = ref(false);
const error = ref('');
const terminal = computed(() =>
  ['completed', 'canceled', 'rejected'].includes(props.record.status)
);
let sequence = 0;
let active = true;
let uploadIntent;
const clearUpload = () => {
  file.value = null;
  uploadIntent = null;
  if (fileInput.value) fileInput.value.value = '';
};
const load = async () => {
  sequence += 1;
  const current = sequence;
  const currentIdentity = identity.value;
  error.value = '';
  try {
    const { data } = await backofficeAPI.documentVersions(props.record.id, {
      document_key: selected.value,
      page: page.value,
    });
    if (!active || current !== sequence || currentIdentity !== identity.value)
      return false;
    result.value = data;
    selected.value = data.selected_key || '';
    const latest = (data.data || []).find(version => version.current);
    expiration.value = latest?.expires_on || '';
    expirationChanged.value = false;
    return true;
  } catch (failure) {
    if (active && current === sequence && currentIdentity === identity.value) {
      error.value = text('DOCUMENTS.LOAD_ERROR');
      if ([401, 403, 404].includes(failure.response?.status)) {
        result.value = null;
        reason.value = '';
        expiration.value = '';
        expirationChanged.value = false;
        clearUpload();
      }
    }
    return false;
  }
};
const run = async action => {
  if (busy.value) return;
  const context = identity.value;
  const token = sequence;
  busy.value = true;
  error.value = '';
  try {
    await action();
    if (!active || context !== identity.value || token !== sequence) return;
    if (await load()) emit('changed');
  } catch (failure) {
    if (!active || context !== identity.value || token !== sequence) return;
    if ([401, 403, 404].includes(failure.response?.status)) {
      result.value = null;
      reason.value = '';
      expiration.value = '';
      expirationChanged.value = false;
      clearUpload();
    }
    error.value =
      failure.response?.data?.message ||
      failure.response?.data?.errors?.join(', ') ||
      text('ACTION_ERROR');
  } finally {
    if (active && context === identity.value) busy.value = false;
  }
};
const upload = () =>
  run(async () => {
    const context = identity.value;
    const key = selected.value;
    const source = file.value;
    if (uploadIntent?.file !== source || uploadIntent?.documentKey !== key)
      uploadIntent = {
        file: source,
        documentKey: key,
        id: crypto.randomUUID(),
      };
    const { data } = await backofficeAPI.uploadDocumentVersion(
      props.record.id,
      key,
      source,
      uploadIntent.id
    );
    if (!active || context !== identity.value) return;
    if (!data?.id) throw new Error('Document upload was not confirmed');
    clearUpload();
    page.value = 1;
  });
const download = version =>
  run(async () => {
    const context = identity.value;
    const token = sequence;
    const { data } = await backofficeAPI.downloadDocumentVersion(
      props.record.id,
      version.id
    );
    if (!active || context !== identity.value || token !== sequence) return;
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = version.filename;
    link.click();
    URL.revokeObjectURL(url);
  });
const decide = (version, status) =>
  run(() =>
    backofficeAPI.decideDocumentVersion(props.record.id, version.id, {
      status,
      reason: reason.value,
      expected_decision_id: version.decision_revision ?? null,
      ...(expirationChanged.value
        ? { expires_on: expiration.value || null }
        : {}),
    })
  );
watch(
  identity,
  () => {
    selected.value = '';
    reason.value = '';
    expiration.value = '';
    expirationChanged.value = false;
    clearUpload();
    busy.value = false;
    page.value = 1;
    result.value = null;
    load();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  active = false;
  clearUpload();
  sequence += 1;
});
const select = () => {
  view.value = 'current';
  page.value = 1;
  reason.value = '';
  result.value = null;
  expiration.value = '';
  expirationChanged.value = false;
  clearUpload();
  load();
};
</script>

<template>
  <section
    class="space-y-4 rounded-xl border border-amber-300 bg-n-solid-2 p-4"
  >
    <div class="flex items-center justify-between gap-3">
      <h3 class="font-bold">{{ text('DOCUMENTS.TITLE') }}</h3>
      <button
        class="rounded-lg border border-n-weak px-3 py-2 text-sm"
        :disabled="busy"
        @click="load"
      >
        {{ text('REFRESH') }}
      </button>
    </div>
    <p class="text-sm text-n-slate-11">{{ text('DOCUMENTS.NOTE') }}</p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-rose-50 p-3 text-sm text-rose-900"
    >
      {{ error }}
    </p>
    <template v-if="result?.requirements.length">
      <label class="block text-sm font-semibold">
        {{ text('DOCUMENTS.REQUIREMENT') }}
        <select
          v-model="selected"
          class="mt-1 block w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          :disabled="busy"
          @change="select"
        >
          <option
            v-for="row in result.requirements"
            :key="row.key"
            :value="row.key"
          >
            {{ row.label }}
          </option>
        </select>
      </label>
      <nav
        class="flex gap-2"
        :aria-label="text('DOCUMENTS.TITLE')"
      >
        <button
          v-for="item in ['current', 'history']"
          :key="item"
          class="rounded-lg border px-3 py-2 text-sm font-semibold"
          :class="
            view === item
              ? 'border-amber-700 bg-amber-700 text-white'
              : 'border-amber-300 bg-n-solid-2 text-amber-800 dark:text-amber-200'
          "
          :disabled="busy"
          @click="
            view = item;
            page = 1;
            load();
          "
        >
          {{ text(`DOCUMENTS.${item.toUpperCase()}`) }}
        </button>
      </nav>
      <form
        v-if="view === 'current'"
        class="flex flex-wrap items-end gap-3"
        @submit.prevent="upload"
      >
        <label class="min-w-0 flex-1 text-sm">
          {{ text('DOCUMENTS.NEW_VERSION') }}
          <input
            ref="fileInput"
            type="file"
            accept=".pdf,.png,.jpg,.jpeg"
            class="mt-2 block w-full text-sm"
            :disabled="busy || terminal"
            @change="file = $event.target.files[0]"
          />
        </label>
        <button
          :disabled="busy || terminal || !file"
          class="rounded-lg bg-amber-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-40"
        >
          {{ text('DOCUMENTS.UPLOAD') }}
        </button>
      </form>
      <label
        v-if="view === 'current'"
        class="block text-sm"
      >
        {{ text('DOCUMENTS.REASON') }}
        <textarea
          v-model="reason"
          maxlength="2000"
          rows="2"
          class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-2"
          :disabled="busy || terminal"
        />
      </label>
      <label
        v-if="view === 'current'"
        class="block text-sm"
      >
        {{ text('DOCUMENTS.EXPIRES_ON') }}
        <input
          v-model="expiration"
          type="date"
          :disabled="busy || terminal"
          class="mt-1 block rounded-lg border border-n-weak bg-n-solid-2 p-2"
          @input="expirationChanged = true"
        />
        <span class="mt-1 block text-xs text-n-slate-11">
          {{ text('DOCUMENTS.EXPIRY_NOTE') }}
        </span>
      </label>
      <article
        v-for="version in visibleVersions"
        :key="version.id"
        class="space-y-3 rounded-xl border border-n-weak p-3 text-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div class="min-w-0">
            <b class="break-all">{{ version.filename }}</b>
            <p class="mt-1 text-xs text-n-slate-11">
              {{ text('DOCUMENTS.VERSION') }} {{ version.version }}
              {{ text('SEPARATOR') }} {{ date(version.created_at) }}
              {{ text('SEPARATOR') }}
              {{ text(`DOCUMENTS.STATES.${version.status}`) }}
            </p>
          </div>
          <button
            class="rounded-lg border border-n-weak px-3 py-2"
            :disabled="busy || version.safety?.state !== 'clean'"
            @click="download(version)"
          >
            {{ text('FORM.DOWNLOAD') }}
          </button>
        </div>
        <p
          class="rounded-lg border p-3 text-xs"
          :class="
            version.safety?.state === 'clean'
              ? 'border-n-teal-6 bg-n-teal-3 text-n-teal-12'
              : 'border-n-amber-6 bg-n-amber-3 text-n-amber-12'
          "
        >
          {{ text(`DOCUMENTS.SAFETY.${version.safety?.state || 'pending'}`) }}
        </p>
        <button
          v-if="version.safety?.state !== 'clean' && !terminal"
          type="button"
          :disabled="busy"
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-n-blue-12 disabled:opacity-40"
          @click="
            run(() =>
              backofficeAPI.recheckDocumentVersion(record.id, version.id)
            )
          "
        >
          {{ text('DOCUMENTS.RECHECK') }}
        </button>
        <details
          v-if="version.analysis"
          :open="view === 'current'"
          class="rounded-lg bg-n-alpha-2 p-3"
        >
          <summary class="cursor-pointer font-semibold">
            {{ text('DOCUMENTS.ANALYSIS') }}
          </summary>
          <p class="mt-1 text-xs text-n-slate-11">
            {{ version.analysis.analyzer_version }} {{ text('SEPARATOR') }}
            {{ version.analysis.evidence.engine }} {{ text('SEPARATOR') }}
            {{ date(version.analysis.created_at) }}
          </p>
          <p
            v-if="version.analysis.evidence.reason"
            class="mt-2 text-amber-700 dark:text-amber-300"
          >
            {{ text('DOCUMENTS.UNAVAILABLE') }}
          </p>
          <ul class="mt-2 space-y-1">
            <li
              v-for="(value, key) in version.analysis.evidence.checks"
              :key="key"
            >
              {{ text(`DOCUMENTS.CHECKS.${key}`) }}{{ text('FIELD_SEPARATOR') }}
              <b>{{ text(`DOCUMENTS.RESULTS.${value}`) }}</b>
            </li>
          </ul>
          <p
            v-if="version.analysis.evidence.ocr_confidence != null"
            class="mt-2 text-xs"
          >
            {{ text('DOCUMENTS.OCR_CONFIDENCE') }}
            {{ version.analysis.evidence.ocr_confidence }}{{ text('PERCENT') }}
          </p>
          <p class="mt-2 text-xs text-n-slate-11">
            {{ text('DOCUMENTS.LIMIT') }}
            {{ version.analysis.evidence.page_limit || 0 }}
          </p>
        </details>
        <div
          v-if="
            view === 'current' &&
            version.current &&
            (version.analysis ||
              (version.safety && version.safety.state !== 'pending')) &&
            !terminal
          "
          class="flex gap-2"
        >
          <button
            v-for="status in ['approved', 'rejected']"
            :key="status"
            :disabled="
              busy ||
              !reason.trim() ||
              (status === 'approved' &&
                (version.safety?.state !== 'clean' || !version.analysis))
            "
            class="rounded-lg border border-n-strong px-3 py-2 font-semibold disabled:opacity-40"
            @click="decide(version, status)"
          >
            {{ text(status === 'approved' ? 'FORM.APPROVE' : 'FORM.REJECT') }}
          </button>
        </div>
        <p
          v-if="!version.current"
          class="text-xs text-n-slate-11"
        >
          {{ text('DOCUMENTS.SUPERSEDED') }}
        </p>
        <details
          v-if="version.decisions.length"
          class="text-xs"
        >
          <summary class="cursor-pointer font-semibold">
            {{ text('DOCUMENTS.DECISIONS') }}
          </summary>
          <p
            v-for="decision in version.decisions"
            :key="decision.id"
            class="mt-2"
          >
            {{ date(decision.created_at) }} {{ text('SEPARATOR') }}
            {{ text(`DOCUMENTS.STATES.${decision.status}`) }}
            {{ text('SEPARATOR') }}
            {{ decision.reason }}
            <span v-if="decision.expires_on">
              {{ text('SEPARATOR') }} {{ text('DOCUMENTS.EXPIRES_ON') }}
              {{ decision.expires_on }} ({{ decision.validity_timezone }})
            </span>
          </p>
        </details>
      </article>
      <div
        v-if="view === 'history'"
        class="flex items-center justify-end gap-3 text-sm"
      >
        <button
          :disabled="busy || result.meta.page <= 1"
          @click="
            page--;
            load();
          "
        >
          {{ text('PREVIOUS') }}
        </button>
        <span>
          {{ result.meta.page }} {{ text('PAGE_SEPARATOR') }}
          {{ result.meta.pages }}
        </span>
        <button
          :disabled="busy || result.meta.page >= result.meta.pages"
          @click="
            page++;
            load();
          "
        >
          {{ text('NEXT') }}
        </button>
      </div>
    </template>
    <p
      v-else-if="result"
      class="text-sm text-n-slate-11"
    >
      {{ text('DOCUMENTS.EMPTY') }}
    </p>
  </section>
</template>
