<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import api from 'dashboard/api/crm/backofficeDossiers';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({ record: { type: Object, required: true } });
const route = useRoute();
const store = useStore();
const { text, date } = useBackofficePresentation();
const result = ref(null);
const opened = ref(false);
const busy = ref(false);
const confirmed = ref(false);
const error = ref('');
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.record.id,
    props.record.status,
    store.getters.getCurrentUser,
    store.getters.getCurrentRole,
  ])
);
let generation = 0;
let controller;
const perform = async (action = 'list', value = 1) => {
  if (busy.value) return;
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  const options = { signal: controller.signal };
  const args = [route.params.accountId, props.record.id];
  busy.value = true;
  error.value = '';
  confirmed.value = false;
  try {
    if (action === 'seal') {
      await api.seal(...args, result.value.candidate_digest, options);
      if (token !== generation) return;
    }
    if (action === 'download') {
      const { data } = await api.download(...args, value, options);
      if (token !== generation) return;
      const url = URL.createObjectURL(data);
      try {
        const link = document.createElement('a');
        link.href = url;
        link.download = `backoffice-${props.record.id}-sealed-${value}.tar.gz`;
        link.click();
      } finally {
        URL.revokeObjectURL(url);
      }
    } else {
      const { data } = await api.list(...args, value, options);
      if (token === generation) result.value = data;
    }
  } catch {
    if (token === generation) {
      result.value = null;
      error.value = text('COMPLETION_DOSSIER.ERROR');
    }
  } finally {
    if (token === generation) busy.value = false;
  }
};
const open = () => {
  opened.value = true;
  perform();
};
const clear = () => {
  generation += 1;
  controller?.abort();
  result.value = null;
  confirmed.value = false;
  busy.value = false;
  opened.value = false;
  error.value = '';
};
watch(identity, clear);
onBeforeUnmount(clear);
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-xl border border-n-violet-6 bg-n-violet-2 p-3"
    :aria-busy="busy"
  >
    <button
      type="button"
      :disabled="busy"
      :aria-expanded="opened"
      class="rounded-lg border border-n-violet-7 px-3 py-2 text-sm font-semibold text-n-violet-12 disabled:opacity-50"
      @click="open"
    >
      {{ text('COMPLETION_DOSSIER.TITLE') }}
    </button>
    <div
      v-if="opened"
      class="min-w-0 space-y-3"
    >
      <p class="text-sm text-n-slate-11">
        {{ text('COMPLETION_DOSSIER.NOTE') }}
      </p>
      <p
        v-if="error"
        role="alert"
        class="text-sm text-n-ruby-11"
      >
        {{ error }}
      </p>
      <p
        v-if="busy"
        role="status"
      >
        {{ text('COMPLETION_DOSSIER.LOADING') }}
      </p>
      <template v-if="result">
        <p
          v-if="!result.data.length"
          class="text-sm text-n-slate-11"
        >
          {{ text('COMPLETION_DOSSIER.EMPTY') }}
        </p>
        <article
          v-for="row in result.data"
          :key="row.id"
          class="min-w-0 space-y-2 rounded-lg border border-n-violet-6 bg-n-solid-2 p-3 text-sm"
        >
          <b>
            {{ text('COMPLETION_DOSSIER.VERSION') }} {{ row.number }}
            {{ date(row.sealed_at) }}
          </b>
          <p>
            {{
              text(
                row.current
                  ? 'COMPLETION_DOSSIER.CURRENT'
                  : 'COMPLETION_DOSSIER.HISTORICAL'
              )
            }}
          </p>
          <p class="break-all text-xs">
            {{ text('COMPLETION_PACKAGE_HASH') }} {{ row.archive_sha256 }}
          </p>
          <button
            type="button"
            :disabled="busy || !row.can_download"
            class="rounded-lg bg-n-violet-9 px-3 py-2 text-white disabled:opacity-50"
            @click="perform('download', row.id)"
          >
            {{ text('COMPLETION_DOSSIER.DOWNLOAD') }}
          </button>
          <p
            v-if="!row.can_download"
            class="text-n-ruby-11"
          >
            {{ text('COMPLETION_DOSSIER.BLOCKED') }}
          </p>
        </article>
        <div
          v-if="result.can_seal"
          class="space-y-3 rounded-lg border border-n-violet-6 bg-n-solid-2 p-3"
        >
          <label class="flex items-start gap-2 text-sm">
            <input
              v-model="confirmed"
              type="checkbox"
              :disabled="busy"
              class="mt-1 shrink-0"
            />
            <span>{{ text('COMPLETION_DOSSIER.CONFIRM') }}</span>
          </label>
          <button
            type="button"
            :disabled="busy || !confirmed"
            class="rounded-lg bg-n-teal-9 px-3 py-2 text-sm text-white disabled:opacity-50"
            @click="perform('seal')"
          >
            {{ text('COMPLETION_DOSSIER.SEAL') }}
          </button>
        </div>
        <nav
          class="flex flex-wrap items-center justify-between gap-2"
          :aria-label="text('COMPLETION_DOSSIER.PAGES')"
        >
          <button
            type="button"
            :disabled="busy || result.meta.page <= 1"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            @click="perform('list', result.meta.page - 1)"
          >
            {{ text('PREVIOUS') }}
          </button>
          <span>
            {{ result.meta.page }} {{ text('COMPLETION_DOSSIER.OF') }}
            {{ result.meta.pages }}
          </span>
          <button
            type="button"
            :disabled="busy || result.meta.page >= result.meta.pages"
            class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
            @click="perform('list', result.meta.page + 1)"
          >
            {{ text('NEXT') }}
          </button>
        </nav>
      </template>
    </div>
  </section>
</template>
