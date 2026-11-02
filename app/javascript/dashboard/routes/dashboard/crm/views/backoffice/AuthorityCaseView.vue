<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import api from 'dashboard/api/crm/backofficeAuthorities';
import { useBackofficePresentation } from './useBackofficePresentation';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  requestId: { type: [String, Number], required: true },
  data: { type: Object, required: true },
});
const emit = defineEmits(['denied']);
const { text, date } = useBackofficePresentation();
const downloading = ref(false);
const error = ref('');
let generation = 0;
let controller;
const identity = computed(() =>
  JSON.stringify([props.accountId, props.requestId, props.data.proposal.id])
);
const people = computed(() => props.data.signers.signers || []);
const person = key => people.value.find(row => row.key === key);
const signerRule = proof => {
  const side = person(proof.signer_key)?.party;
  return [
    text(`CONTRACT_SIGNERS.PARTIES.${side}`),
    text(`CONTRACT_SIGNERS.MODES.${props.data.signers[`${side}_mode`]}`),
    text('CONTRACT_SIGNERS.REQUIRED'),
  ].join(' · ');
};
const validity = proof =>
  [
    text(`CONTRACT_AUTHORITY.BASES.${proof.basis}`),
    proof.valid_from,
    proof.no_expiry ? text('CONTRACT_AUTHORITY.NO_EXPIRY') : proof.valid_until,
  ].join(' · ');
const requestLabel = request =>
  `${text('CONTRACT_AUTHORITY.APPROVAL')} #${request.id} · ${text(`CONTRACT_AUTHORITY.REQUEST_STATES.${request.state}`)}`;
const status = computed(() => props.data.status?.status || 'unavailable');
const blockedFacts = computed(() =>
  Object.entries(props.data.status?.facts || {})
    .filter(([, value]) => value === false)
    .map(([key]) => key)
);
const amount = computed(() => {
  const value =
    props.data.context?.financials?.contract_total_cents ??
    props.data.context?.financials?.total_cents;
  if (!Number.isSafeInteger(value)) return '—';
  return new Intl.NumberFormat('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value / 100);
});
const download = async (kind, id) => {
  if (downloading.value) return;
  const token = generation;
  downloading.value = true;
  error.value = '';
  try {
    const args = [props.accountId, props.requestId, props.data.proposal.id];
    if (kind === 'document') args.push(id);
    const { data } = await api[kind](...args, { signal: controller.signal });
    if (token !== generation) return;
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    const extension =
      { 'application/pdf': '.pdf', 'image/png': '.png', 'image/jpeg': '.jpg' }[
        data.type
      ] || '';
    link.download =
      kind === 'pdf'
        ? `contrato-v${props.data.version.number}.pdf`
        : `evidencia-${id}${extension}`;
    link.click();
    URL.revokeObjectURL(url);
  } catch (failure) {
    if (token !== generation) return;
    if ([401, 403, 404].includes(failure.response?.status)) emit('denied');
    error.value = text('CONTRACT_AUTHORITY.EVIDENCE_ERROR');
  } finally {
    if (token === generation) downloading.value = false;
  }
};
watch(
  identity,
  () => {
    generation += 1;
    controller?.abort();
    controller = new AbortController();
    downloading.value = false;
    error.value = '';
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section class="space-y-4">
    <header
      class="rounded-xl border border-n-violet-6 bg-n-violet-3 p-4 text-n-violet-12"
    >
      <h3 class="font-bold">
        {{ `${text('CONTRACT_AUTHORITY.CASE')} #${data.proposal.id}` }}
      </h3>
      <p class="mt-1 text-sm">
        {{
          `${text('CONTRACT_VERSIONS.VERSION')} ${data.version.number} · ${text('CONTRACT_AUTHORITY.REVISION')} ${data.proposal.revision}`
        }}
      </p>
      <p
        class="mt-2 rounded-lg px-3 py-2 font-semibold"
        :class="
          status === 'verified'
            ? 'bg-n-teal-3 text-n-teal-12'
            : 'bg-n-amber-3 text-n-amber-12'
        "
      >
        {{ text(`CONTRACT_AUTHORITY.STATES.${status}`) }}
      </p>
    </header>
    <p
      class="rounded-lg border border-n-amber-6 bg-n-amber-3 p-3 text-sm text-n-amber-12"
    >
      {{ text('CONTRACT_AUTHORITY.NOTE') }}
    </p>
    <ul
      v-if="blockedFacts.length"
      class="space-y-1 rounded-lg border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-12"
    >
      <li v-for="fact in blockedFacts" :key="fact">
        {{ text(`CONTRACT_AUTHORITY.FACTS.${fact}`) }}
      </li>
    </ul>
    <p v-if="error" role="alert" class="text-sm text-n-ruby-11">{{ error }}</p>
    <dl
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm sm:grid-cols-2"
    >
      <div v-for="side in ['customer', 'issuer_company']" :key="side">
        <dt class="text-n-slate-11">
          {{ text(`CONTRACT_AUTHORITY.PARTIES.${side}`) }}
        </dt>
        <dd class="font-semibold">
          {{ data.context?.[side]?.legal_name || data.context?.[side]?.name }}
        </dd>
      </div>
      <div>
        <dt class="text-n-slate-11">{{ text('CONTRACT_AUTHORITY.ORIGIN') }}</dt>
        <dd>
          {{
            [
              data.context?.order_number,
              data.context?.proposal_number || '—',
            ].join(' · ')
          }}
        </dd>
      </div>
      <div>
        <dt class="text-n-slate-11">{{ text('CONTRACT_AUTHORITY.REASON') }}</dt>
        <dd class="whitespace-pre-wrap">{{ data.proposal.change_reason }}</dd>
      </div>
      <div>
        <dt class="text-n-slate-11">
          {{ text('CONTRACT_AUTHORITY.NATIVE_VALUE') }}
        </dt>
        <dd>{{ amount }}</dd>
      </div>
      <div>
        <dt class="text-n-slate-11">
          {{ text('CONTRACT_AUTHORITY.FINANCIAL_TERMS') }}
        </dt>
        <dd>{{ data.context?.contract?.payment_condition || '—' }}</dd>
      </div>
    </dl>
    <button
      type="button"
      :disabled="downloading"
      class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-sm font-semibold text-n-blue-12 disabled:opacity-50"
      @click="download('pdf')"
    >
      {{ text('CONTRACT_AUTHORITY.EXACT_PDF') }}
    </button>
    <article
      v-for="proof in data.proposal.proofs"
      :key="proof.signer_key"
      class="space-y-2 rounded-xl border border-n-weak bg-n-solid-2 p-4 text-sm"
    >
      <h4 class="font-semibold">{{ person(proof.signer_key)?.name }}</h4>
      <p>{{ signerRule(proof) }}</p>
      <p>
        {{
          [
            person(proof.signer_key)?.email,
            person(proof.signer_key)?.personal_tax_identifier_masked,
          ].join(' · ')
        }}
      </p>
      <p>
        {{ validity(proof) }}
      </p>
      <p class="whitespace-pre-wrap">{{ proof.reason }}</p>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="id in proof.document_version_ids"
          :key="id"
          type="button"
          :disabled="downloading"
          class="rounded-lg border border-n-blue-6 bg-n-blue-3 px-3 py-2 text-n-blue-12 disabled:opacity-50"
          @click="download('document', id)"
        >
          {{ `${text('CONTRACT_AUTHORITY.EVIDENCE')} #${id}` }}
        </button>
      </div>
    </article>
    <p class="text-xs text-n-slate-11">
      {{ text('CONTRACT_AUTHORITY.CREATED') }}
      {{ date(data.proposal.created_at) }}
    </p>
    <div class="flex flex-wrap gap-2">
      <template
        v-for="request in data.status?.requests || []"
        :key="request.id"
      >
        <router-link
          v-if="request.readable"
          :to="{
            name: 'jrc_approvals',
            params: { accountId, screen: 'inbox', id: request.id },
          }"
          class="rounded-lg border border-n-violet-6 bg-n-violet-3 px-3 py-2 text-sm text-n-violet-12"
        >
          {{ requestLabel(request) }}
        </router-link>
        <p
          v-else
          class="rounded-lg border border-n-weak p-3 text-sm text-n-slate-11"
        >
          {{ requestLabel(request) }}
        </p>
      </template>
    </div>
  </section>
</template>
