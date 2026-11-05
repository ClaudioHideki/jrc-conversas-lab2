<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue';
import api from 'dashboard/api/crm/backofficeSignatures';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import SignatureEvidencePanel from './SignatureEvidencePanel.vue';
import { useBackofficePresentation } from './useBackofficePresentation';
import { signatureEventKey } from './signaturePresentation';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  requestId: { type: [Number, String], required: true },
  deliveryId: { type: Number, required: true },
});
const emit = defineEmits(['close', 'denied', 'updated']);
const { text, date } = useBackofficePresentation();
const dialog = ref(null);
const result = ref(null);
const loading = ref(false);
const error = ref('');
let active = true;
let controller;
const load = async (page = 1) => {
  controller?.abort();
  controller = new AbortController();
  loading.value = true;
  result.value = null;
  error.value = '';
  try {
    const { data } = await api.show(
      props.accountId,
      props.requestId,
      props.deliveryId,
      page,
      { signal: controller.signal }
    );
    if (active) result.value = data;
  } catch (failure) {
    if (!active) return;
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
    else error.value = text('CONTRACT_SIGNATURES.ERROR');
  } finally {
    if (active) loading.value = false;
  }
};
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(() => {
  active = false;
  controller?.abort();
  result.value = null;
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="text('CONTRACT_SIGNATURES.HISTORY')"
    :description="text('CONTRACT_SIGNATURES.HISTORY_DESCRIPTION')"
    :show-confirm-button="false"
    show-close-button
    overflow-y-auto
    :use-form="false"
    width="2xl"
    @close="emit('close')"
  >
    <p v-if="loading" role="status" class="text-sm text-n-slate-11">
      {{ text('CONTRACT_SIGNATURES.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 text-n-ruby-12"
    >
      {{ error }}
    </p>
    <section v-if="result" class="space-y-3" :aria-busy="loading">
      <SignatureEvidencePanel
        :account-id="accountId"
        :request-id="requestId"
        :delivery-id="deliveryId"
        @denied="emit('denied')"
        @updated="emit('updated')"
      />
      <p class="text-sm text-n-slate-11">
        {{ text('CONTRACT_SIGNATURES.VERSION') }}
        {{ result.delivery.version_number }}
      </p>
      <p v-if="!result.data.length" class="text-sm text-n-slate-11">
        {{ text('CONTRACT_SIGNATURES.NO_EVENTS') }}
      </p>
      <article
        v-for="event in result.data"
        :key="event.id"
        class="rounded-lg border border-n-weak bg-n-solid-2 p-3 text-sm"
      >
        <b>{{
          text(`CONTRACT_SIGNATURES.EVENTS.${signatureEventKey(event.kind)}`)
        }}</b>
        <p class="mt-1 text-xs text-n-slate-11">{{ date(event.created_at) }}</p>
      </article>
      <nav
        class="flex justify-between gap-2"
        :aria-label="text('CONTRACT_SIGNATURES.EVENT_PAGES')"
      >
        <button
          type="button"
          :disabled="loading || result.meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="load(result.meta.page - 1)"
        >
          {{ text('PREVIOUS') }}
        </button>
        <button
          type="button"
          :disabled="loading || result.meta.page >= result.meta.pages"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="load(result.meta.page + 1)"
        >
          {{ text('NEXT') }}
        </button>
      </nav>
    </section>
  </Dialog>
</template>
