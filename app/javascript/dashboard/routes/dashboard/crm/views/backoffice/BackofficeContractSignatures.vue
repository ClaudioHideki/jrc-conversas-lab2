<script setup>
import { ref, watch } from 'vue';
import { useBackofficePresentation } from './useBackofficePresentation';
import { useSignatureHistory } from './useSignatureHistory';
import { signatureStateKey, signatureTone } from './signaturePresentation';
import SignatureDeliveryDetails from './SignatureDeliveryDetails.vue';
import SignatureIntentDialog from './SignatureIntentDialog.vue';

const props = defineProps({ record: { type: Object, required: true } });
const { text, date } = useBackofficePresentation();
const {
  accountId,
  identity,
  result,
  selection,
  loading,
  accessDenied,
  error,
  load,
  changePage,
  deny,
} = useSignatureHistory(props);
const intent = ref(null);
const notice = ref('');
watch(identity, () => {
  intent.value = null;
  notice.value = '';
});
watch(accessDenied, denied => {
  if (!denied) return;
  intent.value = null;
  notice.value = '';
});
const registered = async state => {
  intent.value = null;
  notice.value = text(
    state === 'canceled'
      ? 'CONTRACT_SIGNATURES.CANCELED_PREPARED'
      : 'CONTRACT_SIGNATURES.REGISTERED'
  );
  await load();
};
</script>

<template>
  <section
    class="space-y-4"
    :aria-busy="loading"
  >
    <header
      class="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-n-blue-6 bg-n-blue-3 p-4"
    >
      <div>
        <h3 class="font-bold text-n-blue-12">
          {{ text('CONTRACT_SIGNATURES.TITLE') }}
        </h3>
        <p class="mt-1 text-sm text-n-slate-11">
          {{ text('CONTRACT_SIGNATURES.DESCRIPTION') }}
        </p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          type="button"
          :disabled="loading || accessDenied"
          class="rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-semibold text-white disabled:opacity-50"
          @click="intent = { delivery: null }"
        >
          {{ text('CONTRACT_SIGNATURES.SEND') }}
        </button>
        <button
          type="button"
          :disabled="loading"
          class="rounded-lg border border-n-blue-6 bg-n-solid-2 px-3 py-2 text-sm text-n-blue-12 disabled:opacity-50"
          @click="load"
        >
          {{ text('REFRESH') }}
        </button>
      </div>
    </header>
    <p
      v-if="loading"
      role="status"
      class="text-sm text-n-slate-11"
    >
      {{ text('CONTRACT_SIGNATURES.LOADING') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="rounded-lg bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
    >
      {{ error }}
    </p>
    <p
      v-if="notice && !error"
      role="status"
      class="rounded-lg border border-n-blue-6 bg-n-blue-3 p-3 text-sm text-n-blue-12"
    >
      {{ notice }}
    </p>
    <template v-if="result">
      <p
        v-if="
          result.signature_required && !result.signature_requirement_satisfied
        "
        class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
      >
        {{ text('CONTRACT_SIGNATURES.RELEASE_BLOCKED') }}
      </p>
      <p
        v-if="result.contract?.signature_verified === true"
        class="rounded-lg border border-n-teal-6 bg-n-teal-3 p-3 text-sm text-n-teal-12"
      >
        {{ text('CONTRACT_SIGNATURES.VERIFIED') }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{ text('CONTRACT_SIGNATURES.EVIDENCE_NOTICE') }}
      </p>
      <p
        v-if="!result.data.length"
        class="rounded-xl border border-n-weak bg-n-solid-2 p-5 text-sm text-n-slate-11"
      >
        {{ text('CONTRACT_SIGNATURES.EMPTY') }}
      </p>
      <article
        v-for="delivery in result.data"
        :key="delivery.id"
        class="space-y-3 rounded-xl border border-n-weak bg-n-solid-2 p-4"
      >
        <div class="flex flex-wrap items-center justify-between gap-3">
          <b>
            {{ text('CONTRACT_SIGNATURES.VERSION') }}
            {{ delivery.version_number }}
          </b>
          <span
            class="rounded-lg border px-3 py-1 text-sm font-semibold"
            :class="signatureTone(delivery.state)"
          >
            {{
              text(
                `CONTRACT_SIGNATURES.STATES.${signatureStateKey(delivery.state)}`
              )
            }}
          </span>
        </div>
        <dl class="grid grid-cols-1 gap-3 text-sm sm:grid-cols-2">
          <div>
            <dt class="text-n-slate-11">
              {{ text('CONTRACT_SIGNATURES.PROVIDER') }}
            </dt>
            <dd>
              {{
                text(
                  delivery.provider === 'docusign'
                    ? 'CONTRACT_SIGNATURES.DOCUSIGN'
                    : 'CONTRACT_SIGNATURES.OTHER_PROVIDER'
                )
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ text('CONTRACT_SIGNATURES.ENVIRONMENT') }}
            </dt>
            <dd>
              {{
                text(
                  delivery.environment === 'demo'
                    ? 'CONTRACT_SIGNATURES.DEMO'
                    : 'CONTRACT_SIGNATURES.PRODUCTION'
                )
              }}
            </dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ text('CONTRACT_SIGNATURES.CONNECTION_REVISION') }}
            </dt>
            <dd>{{ delivery.connection_revision }}</dd>
          </div>
          <div>
            <dt class="text-n-slate-11">
              {{ text('CONTRACT_SIGNATURES.LAST_EVENT') }}
            </dt>
            <dd>{{ date(delivery.last_event_at) }}</dd>
          </div>
          <div class="min-w-0 sm:col-span-2">
            <dt class="text-n-slate-11">
              {{ text('CONTRACT_SIGNATURES.REFERENCE') }}
            </dt>
            <dd class="break-all">
              {{
                delivery.external_id ||
                text('CONTRACT_SIGNATURES.NOT_CONFIRMED')
              }}
            </dd>
          </div>
        </dl>
        <button
          type="button"
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm text-n-blue-12"
          @click="selection = delivery.id"
        >
          {{ text('CONTRACT_SIGNATURES.HISTORY') }}
        </button>
        <button
          v-if="delivery.state === 'prepared'"
          type="button"
          class="ml-2 rounded-lg border border-n-ruby-6 bg-n-ruby-3 px-3 py-2 text-sm text-n-ruby-12"
          @click="intent = { delivery }"
        >
          {{ text('CONTRACT_SIGNATURES.CANCEL_PREPARED') }}
        </button>
      </article>
      <nav
        class="flex justify-between gap-2"
        :aria-label="text('CONTRACT_SIGNATURES.PAGES')"
      >
        <button
          type="button"
          :disabled="loading || result.meta.page <= 1"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="changePage(result.meta.page - 1)"
        >
          {{ text('PREVIOUS') }}
        </button>
        <button
          type="button"
          :disabled="loading || result.meta.page >= result.meta.pages"
          class="rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          @click="changePage(result.meta.page + 1)"
        >
          {{ text('NEXT') }}
        </button>
      </nav>
      <SignatureDeliveryDetails
        v-if="selection"
        :key="`${identity}:${selection}`"
        :account-id="accountId"
        :request-id="record.id"
        :delivery-id="selection"
        @close="selection = null"
        @denied="deny"
      />
    </template>
    <SignatureIntentDialog
      v-if="intent"
      :key="identity"
      :account-id="accountId"
      :request-id="record.id"
      :delivery="intent.delivery"
      @close="intent = null"
      @registered="registered"
      @denied="
        intent = null;
        deny();
      "
    />
  </section>
</template>
