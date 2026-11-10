<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
import api from 'dashboard/api/crm/backofficeSignatures';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  requestId: { type: [Number, String], required: true },
  deliveryId: { type: Number, required: true },
});
const emit = defineEmits(['updated', 'denied']);
const store = useStore();
const { text } = useBackofficePresentation();
const result = ref(null);
const busy = ref(false);
const error = ref('');
const confirmed = ref(false);
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([
    props.accountId,
    props.requestId,
    props.deliveryId,
    store.getters.getCurrentUser,
    store.getters.getCurrentRole,
  ])
);
const label = computed(() => {
  if (result.value?.accepted) return 'ACCEPTED';
  const states = {
    not_received: 'NOT_RECEIVED',
    pending: 'PENDING',
    verified: 'VERIFIED',
    invalid: 'INVALID',
    source_changed: 'SOURCE_CHANGED',
  };
  return states[result.value?.state] || 'PENDING';
});
const request = async (action = 'load', kind = null) => {
  generation += 1;
  const token = generation;
  controller?.abort();
  controller = new AbortController();
  const options = { signal: controller.signal };
  const args = [props.accountId, props.requestId, props.deliveryId];
  busy.value = true;
  error.value = '';
  confirmed.value = false;
  try {
    let response;
    if (action === 'capture')
      response = await api.captureEvidence(...args, options);
    else if (action === 'accept')
      response = await api.acceptEvidence(
        ...args,
        result.value.source_digest,
        options
      );
    else if (action === 'download')
      response = await api.downloadEvidence(...args, kind, options);
    else response = await api.evidence(...args, options);
    if (token !== generation) return;
    if (action === 'download') {
      const url = URL.createObjectURL(response.data);
      try {
        const link = document.createElement('a');
        link.href = url;
        link.download = `contract-v${result.value.version_number}-${kind}.pdf`;
        link.click();
      } finally {
        URL.revokeObjectURL(url);
      }
    } else {
      result.value = response.data;
      if (action === 'accept') emit('updated');
    }
  } catch (failure) {
    if (token !== generation) return;
    result.value = null;
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
    error.value = text('SIGNATURE_EVIDENCE.ERROR');
  } finally {
    if (token === generation) busy.value = false;
  }
};
watch(
  identity,
  () => {
    result.value = null;
    request();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  result.value = null;
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-xl border border-n-teal-6 bg-n-teal-2 p-3"
    :aria-busy="busy"
  >
    <header class="flex flex-wrap items-center justify-between gap-2">
      <h4 class="font-semibold text-n-teal-12">
        {{ text('SIGNATURE_EVIDENCE.TITLE') }}
      </h4>
      <button
        type="button"
        :disabled="busy"
        class="rounded-lg border border-n-teal-7 px-3 py-2 text-sm disabled:opacity-50"
        @click="request()"
      >
        {{ text('SIGNATURE_EVIDENCE.REFRESH') }}
      </button>
    </header>
    <p class="text-sm text-n-slate-11">
      {{ text('SIGNATURE_EVIDENCE.DESCRIPTION') }}
    </p>
    <p v-if="busy" role="status" class="text-sm">
      {{ text('SIGNATURE_EVIDENCE.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-2 text-sm text-n-ruby-12"
    >
      {{ error }}
    </p>
    <template v-if="result">
      <p role="status" class="break-words text-sm font-semibold">
        {{ text(`SIGNATURE_EVIDENCE.${label}`) }}
      </p>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="result.can_capture"
          type="button"
          :disabled="busy"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm text-white disabled:opacity-50"
          @click="request('capture')"
        >
          {{ text('SIGNATURE_EVIDENCE.CAPTURE') }}
        </button>
        <button
          v-for="file in result.downloads"
          :key="file.kind"
          type="button"
          :disabled="busy || !file.available"
          class="rounded-lg border border-n-teal-7 bg-n-solid-2 px-3 py-2 text-sm disabled:opacity-50"
          @click="request('download', file.kind)"
        >
          {{ text(`SIGNATURE_EVIDENCE.FILES.${file.kind}`) }}
        </button>
      </div>
      <div
        v-if="result.can_accept"
        class="space-y-3 rounded-lg border border-n-blue-6 bg-n-solid-2 p-3"
      >
        <label class="flex items-start gap-2 text-sm">
          <input
            v-model="confirmed"
            type="checkbox"
            :disabled="busy"
            class="mt-1 shrink-0"
          />
          <span>{{ text('SIGNATURE_EVIDENCE.CONFIRM') }}</span>
        </label>
        <button
          type="button"
          :disabled="busy || !confirmed"
          class="rounded-lg bg-n-teal-9 px-3 py-2 text-sm text-white disabled:opacity-50"
          @click="request('accept')"
        >
          {{ text('SIGNATURE_EVIDENCE.ACCEPT') }}
        </button>
      </div>
    </template>
  </section>
</template>
