<script setup>
import { onMounted, ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useBackofficePresentation } from './useBackofficePresentation';
import { useSignatureIntent } from './useSignatureIntent';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  requestId: { type: [Number, String], required: true },
  delivery: { type: Object, default: null },
});
const emit = defineEmits(['close', 'denied', 'registered']);
const { text } = useBackofficePresentation();
const {
  preview,
  confirmed,
  loading,
  error,
  canceling,
  busy,
  available,
  canSubmit,
  load,
  submit,
} = useSignatureIntent(
  {
    accountId: props.accountId,
    requestId: props.requestId,
    delivery: props.delivery,
  },
  emit
);
const dialog = ref(null);
onMounted(() => {
  dialog.value.open();
  load();
});
</script>

<template>
  <Dialog
    ref="dialog"
    :title="
      text(
        canceling
          ? 'CONTRACT_SIGNATURES.CANCEL_PREPARED'
          : 'CONTRACT_SIGNATURES.SEND'
      )
    "
    :show-confirm-button="false"
    :show-cancel-button="false"
    :use-form="false"
    :dismissible="!busy"
    show-close-button
    contained
    overflow-y-auto
    width="2xl"
    @close="emit('close')"
  >
    <form class="space-y-4" :aria-busy="busy" @submit.prevent="submit">
      <p
        class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
      >
        {{
          text(
            canceling
              ? 'CONTRACT_SIGNATURES.CANCEL_PREPARED_NOTICE'
              : 'CONTRACT_SIGNATURES.SEND_NOTICE'
          )
        }}
      </p>
      <p v-if="loading" role="status" class="text-sm text-n-slate-11">
        {{ text('CONTRACT_SIGNATURES.PREPARING') }}
      </p>
      <dl
        v-if="preview?.can_send === true"
        class="space-y-3 rounded-xl border border-n-blue-6 bg-n-blue-3 p-4 text-sm"
      >
        <div>
          <dt class="font-semibold">
            {{ text('CONTRACT_SIGNATURES.PROVIDER') }}
          </dt>
          <dd>
            {{
              text(
                preview.connection.provider === 'docusign'
                  ? 'CONTRACT_SIGNATURES.DOCUSIGN'
                  : 'CONTRACT_SIGNATURES.OTHER_PROVIDER'
              )
            }}
          </dd>
        </div>
        <div>
          <dt class="font-semibold">
            {{ text('CONTRACT_SIGNATURES.VERSION') }}
          </dt>
          <dd>{{ preview.version.number }}</dd>
        </div>
        <div>
          <dt class="font-semibold">
            {{ text('CONTRACT_SIGNATURES.ENVIRONMENT') }}
          </dt>
          <dd>
            {{
              text(
                preview.connection.environment === 'demo'
                  ? 'CONTRACT_SIGNATURES.DEMO'
                  : 'CONTRACT_SIGNATURES.PRODUCTION'
              )
            }}
          </dd>
        </div>
        <div>
          <dt class="font-semibold">
            {{ text('CONTRACT_SIGNATURES.CONNECTION_REVISION') }}
          </dt>
          <dd>{{ preview.connection.revision }}</dd>
        </div>
        <div>
          <dt class="font-semibold">
            {{ text('CONTRACT_SIGNATURES.PDF_HASH') }}
          </dt>
          <dd class="break-all font-mono text-xs">
            {{ preview.version.pdf_sha256 }}
          </dd>
        </div>
      </dl>
      <p
        v-if="error"
        role="alert"
        class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
      >
        {{ error }}
      </p>
      <label
        v-if="available"
        class="flex items-start gap-3 rounded-lg border border-n-weak p-3 text-sm"
      >
        <input
          v-model="confirmed"
          type="checkbox"
          :disabled="busy"
          class="mt-1"
        />
        {{
          text(
            canceling
              ? 'CONTRACT_SIGNATURES.CONFIRM_CANCEL'
              : 'CONTRACT_SIGNATURES.CONFIRM_SEND'
          )
        }}
      </label>
      <div class="flex flex-wrap justify-end gap-2">
        <button
          v-if="!canceling"
          type="button"
          :disabled="busy"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="load"
        >
          {{ text('REFRESH') }}
        </button>
        <button
          type="submit"
          :disabled="!canSubmit"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
        >
          {{
            text(
              canceling
                ? 'CONTRACT_SIGNATURES.CANCEL_PREPARED'
                : 'CONTRACT_SIGNATURES.SEND'
            )
          }}
        </button>
      </div>
    </form>
  </Dialog>
</template>
