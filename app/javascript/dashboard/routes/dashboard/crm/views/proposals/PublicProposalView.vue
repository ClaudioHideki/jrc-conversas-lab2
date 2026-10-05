<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { publicProposalsAPI } from 'dashboard/api/crm';

const route = useRoute();
const proposal = ref(null);
const loading = ref(true);
const error = ref('');
const responding = ref(false);
const notice = ref('');
const signerName = ref('');
const signerDocument = ref('');
const showAcceptanceForm = ref(false);
const acceptedTerms = ref(false);
const showRejectionForm = ref(false);
const rejectionReason = ref('');
const noticeIsError = ref(false);
const formatBRL = cents =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    Number(cents || 0) / 100
  );

const accountId = () => route.params.accountId || route.params.account_id;
const token = () => route.params.token;
const load = async () => {
  try {
    const { data } = await publicProposalsAPI.show(accountId(), token());
    proposal.value = data;
    await publicProposalsAPI.recordView(accountId(), token());
  } catch (requestError) {
    error.value =
      requestError.response?.data?.error ||
      'Proposta não encontrada ou expirada.';
  } finally {
    loading.value = false;
  }
};
const respond = async accepted => {
  if (responding.value) return;
  notice.value = '';
  noticeIsError.value = false;

  if (accepted) {
    if (!signerName.value.trim()) {
      notice.value = 'Informe o nome completo do signatário.';
      noticeIsError.value = true;
      showAcceptanceForm.value = true;
      return;
    }
    if (!signerDocument.value.trim()) {
      notice.value = 'Informe o CPF ou CNPJ do signatário.';
      noticeIsError.value = true;
      showAcceptanceForm.value = true;
      return;
    }
    if (!acceptedTerms.value) {
      notice.value = 'Confirme que leu e aceita os termos desta proposta.';
      noticeIsError.value = true;
      showAcceptanceForm.value = true;
      return;
    }
  }

  responding.value = true;
  try {
    const { data } = accepted
      ? await publicProposalsAPI.accept(accountId(), token(), {
          accepted_by_name: signerName.value.trim(),
          accepted_by_document: signerDocument.value.trim(),
          accepted_terms: acceptedTerms.value,
        })
      : await publicProposalsAPI.reject(
          accountId(),
          token(),
          rejectionReason.value.trim() || 'Recusada pelo cliente'
        );
    notice.value = data.lifecycle_error
      ? `${data.message} Motivo: ${data.lifecycle_error}`
      : data.message;
    noticeIsError.value = Boolean(data.lifecycle_error);
    proposal.value.status = accepted ? 'accepted' : 'rejected';
  } catch (requestError) {
    const errors = requestError.response?.data?.errors;
    notice.value =
      (Array.isArray(errors) && errors.length ? errors.join(' ') : null) ||
      requestError.response?.data?.error ||
      'Não foi possível registrar sua resposta.';
    noticeIsError.value = true;
  } finally {
    responding.value = false;
  }
};

onMounted(load);
</script>

<template>
  <main class="flex min-h-screen justify-center bg-n-surface-1 p-4 sm:py-10">
    <div
      class="w-full max-w-4xl overflow-hidden rounded-2xl border border-n-weak bg-n-solid-2 shadow-xl"
    >
      <div
        v-if="loading"
        class="flex min-h-96 items-center justify-center text-n-slate-11"
      >
        <i class="i-lucide-loader-circle mr-2 size-5 animate-spin" />Carregando
        proposta…
      </div>
      <div v-else-if="error" class="p-12 text-center">
        <i class="i-lucide-file-warning mx-auto size-12 text-n-ruby-11" />
        <h1 class="mt-4 text-xl font-bold text-n-slate-12">
          Proposta indisponível
        </h1>
        <p class="mt-2 text-n-slate-11">{{ error }}</p>
      </div>
      <template v-else>
        <header class="bg-n-blue-11 p-8 text-white">
          <div class="flex flex-wrap items-start justify-between gap-4">
            <div>
              <p
                class="text-xs font-semibold uppercase tracking-[0.18em] text-white/75"
              >
                {{ proposal.proposal_number || `PROP-${proposal.id}` }} · versão
                {{ proposal.version_number || 1 }}
              </p>
              <h1 class="mt-2 text-3xl font-bold">{{ proposal.title }}</h1>
            </div>
            <span
              class="rounded-full bg-white/15 px-3 py-1.5 text-sm font-semibold"
            >
              {{ proposal.status_display || proposal.status }}
            </span>
          </div>
          <p class="mt-3 text-sm text-white/80">
            Válida até
            {{ proposal.valid_until_display || 'data não definida' }} · vigência
            de {{ proposal.term_months || 0 }} meses
          </p>
        </header>
        <div class="p-6 sm:p-8">
          <section
            class="mb-8 grid gap-6 border-b border-n-weak pb-8 sm:grid-cols-2"
          >
            <div>
              <p
                class="text-xs font-bold uppercase tracking-wide text-n-slate-10"
              >
                Preparado para
              </p>
              <p class="mt-2 text-lg font-bold text-n-slate-12">
                {{ proposal.customer?.name || 'Cliente' }}
              </p>
              <p v-if="proposal.customer?.email" class="mt-1 text-n-slate-11">
                {{ proposal.customer.email }}
              </p>
            </div>
            <div class="sm:text-right">
              <p
                class="text-xs font-bold uppercase tracking-wide text-n-slate-10"
              >
                Preparado por
              </p>
              <p class="mt-2 text-lg font-bold text-n-slate-12">
                {{ proposal.account?.name }}
              </p>
              <p class="mt-1 text-n-slate-11">{{ proposal.owner?.name }}</p>
            </div>
          </section>
          <div class="overflow-x-auto rounded-xl border border-n-weak">
            <table class="w-full min-w-[620px] text-left">
              <thead class="bg-n-alpha-2 text-sm font-semibold text-n-slate-11">
                <tr>
                  <th class="p-3">Descrição</th>
                  <th class="p-3 text-right">Qtd.</th>
                  <th class="p-3 text-right">Valor unitário</th>
                  <th class="p-3 text-right">Implantação</th>
                  <th class="p-3 text-right">Primeiro mês</th>
                  <th class="p-3 text-right">Recorrência</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-n-weak">
                <tr
                  v-for="item in proposal.items"
                  :key="`${item.name}-${item.total_cents}`"
                >
                  <td class="p-3">
                    <p class="font-semibold text-n-slate-12">{{ item.name }}</p>
                    <p v-if="item.description" class="text-xs text-n-slate-10">
                      {{ item.description }}
                    </p>
                  </td>
                  <td class="p-3 text-right text-n-slate-11">
                    {{ item.quantity }}
                  </td>
                  <td class="p-3 text-right text-n-slate-11">
                    {{ formatBRL(item.unit_price_cents) }}
                  </td>
                  <td class="p-3 text-right text-n-slate-11">
                    {{ formatBRL(item.setup_fee_cents) }}
                  </td>
                  <td class="p-3 text-right font-semibold text-n-slate-12">
                    {{ formatBRL(item.initial_total_cents) }}
                  </td>
                  <td class="p-3 text-right font-semibold text-n-teal-11">
                    {{ formatBRL(item.recurring_total_cents) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <section class="mt-6 ml-auto max-w-md rounded-xl bg-n-alpha-2 p-4">
            <div class="flex justify-between text-n-slate-11">
              <span>Implantação</span>
              <span>{{ formatBRL(proposal.implementation_cents) }}</span>
            </div>
            <div class="mt-2 flex justify-between text-n-slate-11">
              <span>Mensalidade</span>
              <span>{{ formatBRL(proposal.monthly_cents) }}</span>
            </div>
            <div
              v-if="proposal.total_discount_cents"
              class="mt-2 flex justify-between text-n-ruby-11"
            >
              <span>Descontos</span>
              <span>- {{ formatBRL(proposal.total_discount_cents) }}</span>
            </div>
            <div
              class="mt-3 flex justify-between border-t border-n-weak pt-3 text-xl font-bold text-n-slate-12"
            >
              <span>Total no primeiro mês</span>
              <span>{{ formatBRL(proposal.total_first_month_cents) }}</span>
            </div>
            <div class="mt-2 flex justify-between font-semibold text-n-teal-11">
              <span>Recorrência mensal</span>
              <span>{{ formatBRL(proposal.recurring_monthly_cents) }}</span>
            </div>
          </section>
          <section
            v-if="
              showAcceptanceForm &&
              !['accepted', 'rejected', 'canceled'].includes(proposal.status)
            "
            class="mt-8 rounded-2xl border border-n-teal-6 bg-n-teal-2 p-5"
          >
            <h2 class="font-bold text-n-slate-12">Aceite digital</h2>
            <p class="mt-1 text-sm text-n-slate-10">
              Preencha os dados do signatário. Nome, documento, data/hora e IP
              serão registrados como evidência do aceite.
            </p>
            <div class="mt-4 grid gap-4 sm:grid-cols-2">
              <label class="text-sm font-medium text-n-slate-11">
                Nome completo *
                <input
                  v-model.trim="signerName"
                  class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  autocomplete="name"
                />
              </label>
              <label class="text-sm font-medium text-n-slate-11">
                CPF ou CNPJ *
                <input
                  v-model.trim="signerDocument"
                  class="mt-1 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
                  autocomplete="off"
                />
              </label>
            </div>
            <label class="mt-4 flex items-start gap-3 text-sm text-n-slate-11">
              <input
                v-model="acceptedTerms"
                type="checkbox"
                class="mt-0.5 size-4 rounded border-n-weak"
              />
              <span>Li e aceito os termos desta proposta.</span>
            </label>
            <div
              class="mt-5 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end"
            >
              <button
                type="button"
                :disabled="responding"
                class="rounded-xl border border-n-weak bg-n-solid-2 px-5 py-3 font-semibold text-n-slate-11"
                @click="showAcceptanceForm = false"
              >
                Cancelar
              </button>
              <button
                type="button"
                :disabled="responding"
                class="min-w-48 rounded-xl bg-n-teal-10 px-6 py-3 font-bold text-white hover:bg-n-teal-11 disabled:opacity-50"
                @click="respond(true)"
              >
                {{ responding ? 'Registrando aceite…' : 'Aceitar proposta' }}
              </button>
            </div>
          </section>

          <section
            v-if="
              showRejectionForm &&
              !['accepted', 'rejected', 'canceled'].includes(proposal.status)
            "
            class="mt-8 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-5"
          >
            <h2 class="font-bold text-n-slate-12">
              Solicitar alteração / Recusar
            </h2>
            <p class="mt-1 text-sm text-n-slate-10">
              Informe o motivo ou descreva a alteração necessária.
            </p>
            <textarea
              v-model.trim="rejectionReason"
              class="mt-4 min-h-24 w-full rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2.5"
              placeholder="Motivo da recusa ou alteração solicitada"
            />
            <div
              class="mt-4 flex flex-col-reverse gap-3 sm:flex-row sm:justify-end"
            >
              <button
                type="button"
                :disabled="responding"
                class="rounded-xl border border-n-weak bg-n-solid-2 px-5 py-3 font-semibold text-n-slate-11"
                @click="showRejectionForm = false"
              >
                Cancelar
              </button>
              <button
                type="button"
                :disabled="responding"
                class="rounded-xl bg-n-ruby-10 px-6 py-3 font-bold text-white hover:bg-n-ruby-11 disabled:opacity-50"
                @click="respond(false)"
              >
                {{ responding ? 'Registrando…' : 'Enviar resposta' }}
              </button>
            </div>
          </section>

          <p
            v-if="notice"
            class="mt-6 rounded-xl p-4 text-center font-semibold"
            :class="[
              noticeIsError
                ? 'bg-n-ruby-3 text-n-ruby-11'
                : 'bg-n-blue-3 text-n-blue-11',
            ]"
          >
            {{ notice }}
          </p>
          <div
            v-if="
              !['accepted', 'rejected', 'canceled'].includes(proposal.status) &&
              !showAcceptanceForm &&
              !showRejectionForm
            "
            class="mt-8 flex flex-col-reverse justify-center gap-3 border-t border-n-weak pt-6 sm:flex-row"
          >
            <button
              :disabled="responding"
              class="rounded-xl border border-n-ruby-7 bg-n-solid-2 px-6 py-3 font-bold text-n-ruby-11 disabled:opacity-50"
              @click="showRejectionForm = true"
            >
              Solicitar alteração / Recusar
            </button>
            <button
              :disabled="responding"
              class="min-w-48 rounded-xl bg-n-teal-10 px-6 py-3 font-bold text-white hover:bg-n-teal-11 disabled:opacity-50"
              @click="showAcceptanceForm = true"
            >
              Aceitar proposta
            </button>
          </div>
        </div>
      </template>
    </div>
  </main>
</template>
