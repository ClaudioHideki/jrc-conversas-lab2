<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { backofficeAPI } from 'dashboard/api/crm/commercialCycle';
import BackofficeCompletionDossier from './BackofficeCompletionDossier.vue';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({ record: { type: Object, required: true } });
const route = useRoute();
const { text } = useBackofficePresentation();
const opened = ref(false);
const busy = ref(false);
const manifest = ref(null);
const error = ref('');
const identity = computed(
  () => `${route.params.accountId}:${props.record.id}:${props.record.status}`
);
let generation = 0;
watch(identity, () => {
  generation += 1;
  opened.value = false;
  busy.value = false;
  manifest.value = null;
  error.value = '';
});
onBeforeUnmount(() => {
  generation += 1;
});
const perform = async download => {
  if (busy.value || props.record.status !== 'completed') return;
  const token = generation;
  const context = identity.value;
  const accountId = route.params.accountId;
  const requestId = props.record.id;
  busy.value = true;
  error.value = '';
  try {
    const { data } = await (download
      ? backofficeAPI.downloadCompletionPackage(accountId, requestId)
      : backofficeAPI.completionPackage(accountId, requestId));
    if (token !== generation || context !== identity.value) return;
    if (!download) {
      manifest.value = data;
      return;
    }
    const url = URL.createObjectURL(data);
    try {
      const link = document.createElement('a');
      link.href = url;
      link.download = `backoffice-${requestId}-documents.tar.gz`;
      link.click();
    } finally {
      URL.revokeObjectURL(url);
    }
  } catch {
    if (token === generation) {
      manifest.value = null;
      error.value = text('COMPLETION_PACKAGE_ERROR');
    }
  } finally {
    if (token === generation) busy.value = false;
  }
};
const preview = () => {
  opened.value = true;
  perform(false);
};
</script>

<template>
  <section
    v-if="record.status === 'completed'"
    class="min-w-0 space-y-3 rounded-xl border border-n-strong bg-n-solid-2 p-3"
  >
    <button
      type="button"
      class="rounded-lg border border-teal-400 bg-n-solid-3 px-4 py-2 text-sm font-semibold text-n-slate-12 disabled:opacity-50"
      :disabled="busy"
      :aria-expanded="opened"
      @click="preview"
    >
      {{ text('COMPLETION_PACKAGE') }}
    </button>
    <div
      v-if="opened"
      class="min-w-0 space-y-3"
    >
      <p class="max-w-xl text-sm text-n-slate-11">
        {{ text('COMPLETION_PACKAGE_NOTE') }}
      </p>
      <p
        v-if="busy"
        role="status"
      >
        {{ text('COMPLETION_REPORT_LOADING') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ error }}
      </p>
      <template v-if="manifest">
        <p class="text-sm font-semibold text-n-slate-12">
          {{
            text(
              manifest.coverage === 'incomplete'
                ? 'COMPLETION_PACKAGE_INCOMPLETE'
                : 'COMPLETION_PACKAGE_AVAILABLE'
            )
          }}
        </p>
        <p
          v-if="manifest.missing.length"
          class="text-sm text-n-amber-11"
        >
          {{ text('COMPLETION_PACKAGE_MISSING') }} {{ manifest.missing.length }}
        </p>
        <ul
          v-if="manifest.missing.length"
          class="space-y-1 text-sm text-n-amber-11"
        >
          <li
            v-for="(item, index) in manifest.missing"
            :key="index"
          >
            {{ text(`COMPLETION_PACKAGE_REASON_${item.reason}`) }}
            {{ item.key || '' }}
          </li>
        </ul>
        <ul
          class="max-h-64 space-y-2 overflow-y-auto"
          :aria-label="text('COMPLETION_PACKAGE_FILES')"
        >
          <li
            v-for="file in manifest.files"
            :key="`${file.kind}:${file.id}`"
            class="min-w-0 rounded-lg border border-n-strong p-2 text-xs text-n-slate-12"
          >
            <p class="break-all font-semibold">{{ file.path }}</p>
            <p>
              {{
                text(
                  file.availability === 'available'
                    ? 'COMPLETION_PACKAGE_AVAILABLE'
                    : 'COMPLETION_PACKAGE_BLOCKED'
                )
              }}
            </p>
            <p class="break-all">
              {{ text('COMPLETION_PACKAGE_HASH') }} {{ file.sha256 }}
            </p>
          </li>
        </ul>
        <p
          v-if="!manifest.files.length"
          class="text-sm text-n-slate-11"
        >
          {{ text('COMPLETION_PACKAGE_EMPTY') }}
        </p>
        <button
          type="button"
          class="rounded-lg bg-teal-700 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
          :disabled="busy"
          @click="perform(true)"
        >
          {{ text('COMPLETION_PACKAGE_DOWNLOAD') }}
        </button>
      </template>
    </div>
  </section>
  <BackofficeCompletionDossier :record="record" />
</template>
