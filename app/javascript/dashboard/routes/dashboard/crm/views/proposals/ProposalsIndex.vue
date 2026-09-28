<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, reactive, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { dealsAPI, productsAPI, proposalsAPI } from 'dashboard/api/crm';
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import CrmValueDisplay from '../../components/shared/CrmValueDisplay.vue';
import CrmPageHeader from '../../components/shared/CrmPageHeader.vue';
import CrmStatCard from '../../components/shared/CrmStatCard.vue';
import { formatCrmDate } from '../../utils/dateTime';

const store = useStore();
const route = useRoute();
const { t } = useI18n();
const pdfLoading = ref(false);
const savedForm = ref('');
const itemUpdateFailed = ref(false);
const proposals = computed(
  () => store.getters['jrcCrm/proposals/allProposals'] || []
);
const loading = computed(() => store.getters['jrcCrm/proposals/isLoading']);
const error = computed(() => store.getters['jrcCrm/proposals/error']);
const isAdmin = computed(
  () => store.getters.getCurrentRole === 'administrator'
);
const deals = ref([]);
const products = ref([]);
const dealId = ref('');
const showForm = ref(false);
const saving = ref(false);
const selectedProposal = ref(null);
const loadingDetails = ref(false);
const itemSaving = ref(false);
const sendingChannel = ref('');
const actionWorking = ref('');
const proposalDiscount = ref('');
const itemForm = reactive({ product_id: '', quantity: 1, unit_price: '' });
const hasPendingItem = computed(() => Boolean(itemForm.product_id));
const proposalForm = reactive({
  title: '',
  solution_description: '',
  implementation: '',
  monthly: '',
  valid_until: '',
  term_months: 12,
  commercial_notes: '',
  next_steps: '',
  issuer_company_name: 'Grupo JRC',
  issuer_tax_id: '',
  issuer_unit: '',
  payment_method: '',
  billing_day: '',
  first_billing_days: 0,
  taxes_included: true,
  annual_adjustment_index: 'IPCA',
  renewal_type: 'automatic',
  cancellation_penalty_percent: 0,
  follow_up_enabled: true,
  follow_up_days: 3,
});
const formSnapshot = () =>
  JSON.stringify([proposalForm, proposalDiscount.value]);
const hasUnsavedChanges = computed(
  () => Boolean(selectedProposal.value) && savedForm.value !== formSnapshot()
);
const proposalStats = computed(() => [
  {
    label: 'Propostas',
    value: proposals.value.length,
    detail: 'Total carregado',
    icon: 'i-lucide-files',
    tone: 'blue',
  },
  {
    label: 'Rascunhos',
    value: proposals.value.filter(proposal => proposal.status === 'draft')
      .length,
    detail: 'Em preparação',
    icon: 'i-lucide-file-pen-line',
    tone: 'amber',
  },
  {
    label: 'Enviadas',
    value: proposals.value.filter(proposal =>
      ['sent', 'viewed'].includes(proposal.status)
    ).length,
    detail: 'Aguardando retorno',
    icon: 'i-lucide-send',
    tone: 'iris',
  },
  {
    label: 'Aceitas',
    value: proposals.value.filter(proposal => proposal.status === 'accepted')
      .length,
    detail: 'Confirmadas pelo cliente',
    icon: 'i-lucide-badge-check',
    tone: 'teal',
  },
]);
const proposalProgress = computed(() => {
  const proposal = selectedProposal.value || {};
  const approvalComplete = Boolean(
    proposal.approval?.status === 'approved' ||
      proposal.approval?.status === 'not_required' ||
      ['sent', 'viewed', 'accepted'].includes(proposal.status)
  );
  const wasSent = Boolean(
    proposal.sent_at || ['sent', 'viewed', 'accepted'].includes(proposal.status)
  );
  const wasViewed = Boolean(
    proposal.viewed_at || ['viewed', 'accepted'].includes(proposal.status)
  );
  const wasAccepted = Boolean(
    proposal.accepted_at || proposal.status === 'accepted'
  );
  return [
    { label: 'Rascunho', complete: true, icon: 'i-lucide-file-pen-line' },
    {
      label: 'Aprovação interna',
      complete: approvalComplete,
      icon: 'i-lucide-shield-check',
    },
    { label: 'Enviada', complete: wasSent, icon: 'i-lucide-send' },
    { label: 'Visualizada', complete: wasViewed, icon: 'i-lucide-eye' },
    { label: 'Aceita', complete: wasAccepted, icon: 'i-lucide-badge-check' },
  ];
});

const refresh = () => store.dispatch('jrcCrm/proposals/fetchProposals');
const centsFromInput = value => Math.round(Number(value || 0) * 100);
const moneyInput = cents => (Number(cents || 0) / 100).toFixed(2);
const billingLabel = value =>
  ({
    one_time: 'Cobrança única',
    monthly: 'Mensal',
    annual: 'Anual',
    usage: 'Por uso',
  })[value] ||
  value ||
  'Cobrança única';

const loadProducts = async () => {
  if (products.value.length) return;
  const { data } = await productsAPI.list({ active: true });
  products.value = data;
};

const openForm = async () => {
  try {
    const { data } = await dealsAPI.list({ status: 'open' });
    const contactId = route.query.contactId;
    deals.value =
      typeof contactId === 'string' && /^\d+$/.test(contactId)
        ? data.filter(
            deal =>
              String(deal.contact_id) === contactId ||
              deal.contacts?.some(contact => String(contact.id) === contactId)
          )
        : data;
    dealId.value = deals.value.length === 1 ? deals.value[0].id : '';
    showForm.value = true;
  } catch {
    useAlert('Não foi possível carregar os negócios.');
  }
};

const hydrateProposalForm = data => {
  proposalForm.title = data.title || '';
  proposalForm.solution_description = data.solution_description || '';
  proposalForm.implementation = moneyInput(data.implementation_cents);
  proposalForm.monthly = moneyInput(data.monthly_cents);
  proposalForm.valid_until = data.valid_until || '';
  proposalForm.term_months = data.term_months || 12;
  proposalForm.commercial_notes = data.commercial_notes || '';
  proposalForm.next_steps = data.next_steps || '';
  proposalForm.issuer_company_name = data.issuer?.company_name || 'Grupo JRC';
  proposalForm.issuer_tax_id = data.issuer?.tax_id || '';
  proposalForm.issuer_unit = data.issuer?.unit || '';
  proposalForm.payment_method = data.payment?.method || '';
  proposalForm.billing_day = data.payment?.billing_day || '';
  proposalForm.first_billing_days = data.payment?.first_billing_days || 0;
  proposalForm.taxes_included = data.payment?.taxes_included ?? true;
  proposalForm.annual_adjustment_index =
    data.payment?.annual_adjustment_index || 'IPCA';
  proposalForm.renewal_type = data.payment?.renewal_type || 'automatic';
  proposalForm.cancellation_penalty_percent =
    data.payment?.cancellation_penalty_percent || 0;
  proposalForm.follow_up_enabled = data.follow_up?.enabled ?? true;
  proposalForm.follow_up_days = data.follow_up?.days ?? 3;
  proposalDiscount.value = moneyInput(data.discount_cents);
  savedForm.value = formSnapshot();
};

const openProposal = async proposal => {
  itemUpdateFailed.value = false;
  loadingDetails.value = true;
  selectedProposal.value = proposal;
  try {
    const [{ data }] = await Promise.all([
      proposalsAPI.show(proposal.id),
      loadProducts(),
    ]);
    selectedProposal.value = data;
    hydrateProposalForm(data);
  } catch {
    selectedProposal.value = null;
    useAlert('Não foi possível abrir a proposta.');
  } finally {
    loadingDetails.value = false;
  }
};

const closeProposal = () => {
  selectedProposal.value = null;
  itemForm.product_id = '';
  itemForm.quantity = 1;
  itemForm.unit_price = '';
};

const createProposal = async () => {
  saving.value = true;
  try {
    const { data } = await proposalsAPI.create({ deal_id: dealId.value });
    showForm.value = false;
    dealId.value = '';
    await refresh();
    await openProposal(data);
    useAlert('Proposta criada com os dados do negócio.');
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível criar a proposta.'
    );
  } finally {
    saving.value = false;
  }
};

const applyProposalResponse = async (data, preserveDraft = true) => {
  const dirty = preserveDraft && hasUnsavedChanges.value;
  selectedProposal.value = data;
  if (!dirty) hydrateProposalForm(data);
  await refresh();
};

const persistCommercialData = async (showSuccess = true) => {
  if (!selectedProposal.value || selectedProposal.value.locked) return false;
  saving.value = true;
  try {
    const { data } = await proposalsAPI.update(selectedProposal.value.id, {
      proposal: {
        title: proposalForm.title,
        solution_description: proposalForm.solution_description,
        implementation_cents: centsFromInput(proposalForm.implementation),
        monthly_cents: centsFromInput(proposalForm.monthly),
        valid_until: proposalForm.valid_until || null,
        term_months: Number(proposalForm.term_months || 12),
        commercial_notes: proposalForm.commercial_notes,
        next_steps: proposalForm.next_steps,
        discount_cents: centsFromInput(proposalDiscount.value),
        issuer_company_name: proposalForm.issuer_company_name,
        issuer_tax_id: proposalForm.issuer_tax_id || null,
        issuer_unit: proposalForm.issuer_unit || null,
        payment_method: proposalForm.payment_method || null,
        billing_day: proposalForm.billing_day
          ? Number(proposalForm.billing_day)
          : null,
        first_billing_days: Number(proposalForm.first_billing_days || 0),
        taxes_included: proposalForm.taxes_included,
        annual_adjustment_index: proposalForm.annual_adjustment_index || 'IPCA',
        renewal_type: proposalForm.renewal_type,
        cancellation_penalty_percent: Number(
          proposalForm.cancellation_penalty_percent || 0
        ),
        follow_up_enabled: proposalForm.follow_up_enabled,
        follow_up_days: Number(proposalForm.follow_up_days || 0),
      },
    });
    await applyProposalResponse(data, false);
    if (showSuccess) useAlert('Dados comerciais da proposta atualizados.');
    return true;
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível salvar a proposta.'
    );
    return false;
  } finally {
    saving.value = false;
  }
};

const saveCommercialData = () => persistCommercialData(true);

const selectProduct = () => {
  const product = products.value.find(
    item => String(item.id) === String(itemForm.product_id)
  );
  itemForm.unit_price = product ? moneyInput(product.unit_price_cents) : '';
};

const addItem = async () => {
  if (!selectedProposal.value) return;
  itemSaving.value = true;
  try {
    const { data } = await proposalsAPI.createItem(selectedProposal.value.id, {
      item: {
        product_id: itemForm.product_id,
        quantity: Number(itemForm.quantity || 1),
        unit_price_cents: centsFromInput(itemForm.unit_price),
      },
    });
    await applyProposalResponse(data);
    itemForm.product_id = '';
    itemForm.quantity = 1;
    itemForm.unit_price = '';
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível adicionar o produto.'
    );
  } finally {
    itemSaving.value = false;
  }
};

const updateItem = async item => {
  if (!selectedProposal.value || itemSaving.value) return;
  itemSaving.value = true;
  try {
    const { data } = await proposalsAPI.updateItem(
      selectedProposal.value.id,
      item.id,
      {
        item: {
          quantity: Number(item.quantity || 1),
          unit_price_cents: Number(item.unit_price_cents || 0),
          discount_cents: Number(item.discount_cents || 0),
        },
      }
    );
    await applyProposalResponse(data);
  } catch {
    itemUpdateFailed.value = true;
    useAlert('Não foi possível atualizar o item.');
  } finally {
    itemSaving.value = false;
  }
};

const updateItemPrice = (item, value) => {
  item.unit_price_cents = centsFromInput(value);
  updateItem(item);
};

const updateItemDiscount = (item, value) => {
  item.discount_cents = centsFromInput(value);
  updateItem(item);
};

const removeItem = async item => {
  if (!selectedProposal.value || itemSaving.value) return;
  itemSaving.value = true;
  try {
    const { data } = await proposalsAPI.deleteItem(
      selectedProposal.value.id,
      item.id
    );
    await applyProposalResponse(data);
  } catch {
    useAlert('Não foi possível remover o item.');
  } finally {
    itemSaving.value = false;
  }
};

const publicProposalUrl = proposal =>
  proposal?.public_url ||
  (proposal?.public_path
    ? `${window.location.origin}${proposal.public_path}`
    : '');

const previewProposal = () => {
  const url = publicProposalUrl(selectedProposal.value);
  if (url)
    window.open(
      `${url}${url.includes('?') ? '&' : '?'}preview=1`,
      '_blank',
      'noopener'
    );
};

const downloadPdf = async (proposal = selectedProposal.value) => {
  if (
    !proposal ||
    pdfLoading.value ||
    loadingDetails.value ||
    saving.value ||
    itemSaving.value
  )
    return;
  if (
    proposal.id === selectedProposal.value?.id &&
    (hasUnsavedChanges.value || hasPendingItem.value || itemUpdateFailed.value)
  ) {
    useAlert(t('CRM.PROPOSAL_PDF.UNSAVED'));
    return;
  }
  pdfLoading.value = true;
  try {
    const { data } = await proposalsAPI.pdf(proposal.id);
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `proposta-${proposal.id}-v${proposal.version_number || 1}.pdf`;
    document.body.appendChild(link);
    try {
      link.click();
    } finally {
      link.remove();
      // Chromium needs the blob to remain alive while the download starts.
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    }
  } catch {
    useAlert(t('CRM.PROPOSAL_PDF.ERROR'));
  } finally {
    pdfLoading.value = false;
  }
};

const copyPublicLink = async () => {
  const url = publicProposalUrl(selectedProposal.value);
  if (!url) {
    useAlert('Não foi possível gerar o link público da proposta.');
    return;
  }

  try {
    await navigator.clipboard.writeText(url);
    useAlert('Link público copiado.');
  } catch {
    const input = document.createElement('textarea');
    input.value = url;
    document.body.appendChild(input);
    input.select();
    document.execCommand('copy');
    input.remove();
    useAlert('Link público copiado.');
  }
};

const duplicateProposal = async () => {
  if (!selectedProposal.value || actionWorking.value) return;
  actionWorking.value = 'duplicate';
  try {
    const { data } = await proposalsAPI.duplicate(selectedProposal.value.id);
    await refresh();
    await openProposal(data);
    useAlert('Nova versão criada como rascunho.');
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível duplicar a proposta.'
    );
  } finally {
    actionWorking.value = '';
  }
};

const requestApproval = async () => {
  if (!selectedProposal.value || actionWorking.value) return;
  actionWorking.value = 'approval';
  try {
    const saved = selectedProposal.value.locked
      ? true
      : await persistCommercialData(false);
    if (!saved) return;
    const { data } = await proposalsAPI.requestApproval(
      selectedProposal.value.id
    );
    await applyProposalResponse(data);
    useAlert('Proposta encaminhada para aprovação interna.');
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível solicitar aprovação.'
    );
  } finally {
    actionWorking.value = '';
  }
};

const updateApproval = async (approvalType, decision = 'approved') => {
  if (!selectedProposal.value || actionWorking.value) return;
  actionWorking.value = approvalType;
  try {
    const { data } = await proposalsAPI.approve(
      selectedProposal.value.id,
      approvalType,
      decision
    );
    await applyProposalResponse(data);
    useAlert(
      decision === 'approved'
        ? 'Aprovação registrada.'
        : 'Reprovação registrada.'
    );
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível atualizar a aprovação.'
    );
  } finally {
    actionWorking.value = '';
  }
};

const sendProposal = async channel => {
  if (!selectedProposal.value || sendingChannel.value) return;
  sendingChannel.value = channel;
  try {
    const saved = await persistCommercialData(false);
    if (!saved) return;
    const { data } = await proposalsAPI.sendProposal(
      selectedProposal.value.id,
      channel
    );
    await applyProposalResponse(data.proposal);
    useAlert(
      `Proposta enviada por ${channel === 'email' ? 'e-mail' : 'WhatsApp'} e registrada na conversa.`
    );
  } catch (requestError) {
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível enviar a proposta pela conversa existente.'
    );
  } finally {
    sendingChannel.value = '';
  }
};

const sendFromRow = async (proposal, channel) => {
  await openProposal(proposal);
  await sendProposal(channel);
};

onMounted(async () => {
  await refresh();
  const { proposalId } = route.query;
  if (typeof proposalId === 'string' && /^\d+$/.test(proposalId)) {
    await openProposal({ id: proposalId });
  } else if (route.query.new === '1') {
    await openForm();
  }
});
</script>

<template>
  <div
    class="relative flex h-full flex-col gap-5 overflow-auto bg-n-surface-1 p-4 sm:p-6"
  >
    <CrmPageHeader
      eyebrow="Documentos comerciais"
      title="Propostas"
      description="Crie, acompanhe e envie propostas vinculadas aos negócios."
      icon="i-lucide-file-signature"
      tone="teal"
    >
      <template #actions>
        <button
          type="button"
          class="rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white shadow-md"
          @click="openForm"
        >
          <i class="i-lucide-plus mr-1 size-4" /> Nova proposta
        </button>
      </template>
    </CrmPageHeader>

    <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <CrmStatCard
        v-for="item in proposalStats"
        :key="item.label"
        :label="item.label"
        :value="item.value"
        :detail="item.detail"
        :icon="item.icon"
        :tone="item.tone"
      />
    </div>

    <div
      class="min-h-[360px] flex-1 overflow-auto rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm"
    >
      <table class="min-w-full divide-y divide-n-weak text-sm">
        <thead
          class="sticky top-0 z-10 bg-n-alpha-2 text-left text-xs font-semibold uppercase text-n-slate-10"
        >
          <tr>
            <th class="px-5 py-3">Título</th>
            <th class="px-5 py-3">Negócio</th>
            <th class="px-5 py-3">Status</th>
            <th class="px-5 py-3">Itens</th>
            <th class="px-5 py-3">Total</th>
            <th class="px-5 py-3">Criada em</th>
            <th class="px-5 py-3 text-right">Ações</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-n-weak">
          <tr v-if="loading">
            <td colspan="7" class="px-6 py-12 text-center text-n-slate-10">
              Carregando propostas…
            </td>
          </tr>
          <tr v-else-if="error">
            <td colspan="7" class="px-6 py-12 text-center text-n-ruby-11">
              {{ error }}
            </td>
          </tr>
          <tr v-else-if="!proposals.length">
            <td colspan="7" class="px-6 py-12 text-center text-n-slate-10">
              Nenhuma proposta encontrada.
            </td>
          </tr>
          <tr
            v-for="proposal in proposals"
            :key="proposal.id"
            class="hover:bg-n-alpha-2"
          >
            <td
              class="cursor-pointer px-5 py-4 font-medium"
              @click="openProposal(proposal)"
            >
              <p>{{ proposal.title }}</p>
              <p class="mt-1 text-xs font-normal text-n-slate-10">
                {{ proposal.proposal_number || `PROP-${proposal.id}` }} · versão
                {{ proposal.version_number || 1 }}
              </p>
            </td>
            <td class="px-5 py-4 text-n-slate-11">
              {{ proposal.deal?.title || `Negócio - #${proposal.deal_id}` }}
            </td>
            <td class="px-5 py-4">
              <CrmStatusBadge :value="proposal.status" />
            </td>
            <td class="px-5 py-4 text-n-slate-11">
              {{ proposal.items_count || 0 }}
            </td>
            <td class="px-5 py-4">
              <CrmValueDisplay :cents="proposal.total_cents" />
            </td>
            <td class="px-5 py-4 text-n-slate-10">
              {{
                proposal.created_at_display ||
                formatCrmDate(proposal.created_at)
              }}
            </td>
            <td class="px-5 py-4">
              <div class="flex justify-end gap-1">
                <button
                  type="button"
                  class="rounded-lg border border-n-weak p-2"
                  title="Editar"
                  @click="openProposal(proposal)"
                >
                  <i class="i-lucide-pencil size-4" />
                </button>
                <button
                  type="button"
                  class="rounded-lg border border-n-weak p-2"
                  title="Visualizar proposta"
                  @click="openProposal(proposal).then(() => previewProposal())"
                >
                  <i class="i-lucide-eye size-4" />
                </button>
                <button
                  type="button"
                  class="rounded-lg border border-n-weak p-2"
                  :title="t('CRM.PROPOSAL_PDF.DOWNLOAD')"
                  :disabled="pdfLoading"
                  @click="downloadPdf(proposal)"
                >
                  <i class="i-lucide-file-text size-4" />
                </button>
                <button
                  type="button"
                  class="rounded-lg border border-[#25D366]/40 p-2 text-[#168f48]"
                  title="Enviar por WhatsApp"
                  @click="sendFromRow(proposal, 'whatsapp')"
                >
                  <i class="i-lucide-message-circle size-4" />
                </button>
                <button
                  type="button"
                  class="rounded-lg border border-n-blue-6 p-2 text-n-blue-11"
                  title="Enviar por e-mail"
                  @click="sendFromRow(proposal, 'email')"
                >
                  <i class="i-lucide-mail size-4" />
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div
      v-if="showForm"
      class="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/40 p-4"
      @click.self="showForm = false"
    >
      <form
        class="max-h-[85vh] w-full max-w-lg overflow-y-auto rounded-xl bg-n-solid-2 p-6 shadow-xl"
        @submit.prevent="createProposal"
      >
        <h3 class="text-lg font-bold text-n-slate-12">Criar proposta</h3>
        <p class="mt-1 text-sm text-n-slate-10">
          Produtos, descontos e cliente serão copiados do negócio selecionado.
        </p>
        <label class="mt-5 block text-sm font-medium text-n-slate-11"
          >Negócio
          <select
            v-model="dealId"
            required
            class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
          >
            <option disabled value="">Selecione</option>
            <option v-for="deal in deals" :key="deal.id" :value="deal.id">
              {{ deal.title
              }}{{ deal.contact?.name ? ` — ${deal.contact.name}` : '' }}
            </option>
          </select>
        </label>
        <div class="mt-6 flex justify-end gap-3">
          <button
            type="button"
            class="rounded-lg border border-n-weak px-4 py-2"
            @click="showForm = false"
          >
            Cancelar</button
          ><button
            :disabled="saving"
            class="rounded-lg bg-n-brand px-4 py-2 font-semibold text-white disabled:opacity-50"
          >
            Criar proposta
          </button>
        </div>
      </form>
    </div>

    <div
      v-if="selectedProposal"
      class="absolute inset-0 z-30 overflow-hidden bg-n-surface-1"
      @click.self="closeProposal"
    >
      <aside class="flex h-full w-full flex-col overflow-hidden bg-n-surface-1">
        <div
          class="shrink-0 border-b border-n-weak bg-gradient-to-r from-n-blue-2 via-n-solid-2 to-n-iris-2 px-5 py-4"
        >
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p
                class="text-xs font-semibold uppercase tracking-[0.16em] text-n-brand"
              >
                {{ selectedProposal.proposal_number || 'Proposta comercial' }} ·
                versão {{ selectedProposal.version_number || 1 }}
              </p>
              <h3 class="mt-1 text-2xl font-bold text-n-slate-12">
                {{ selectedProposal.title }}
              </h3>
              <p class="mt-1 text-sm text-n-slate-10">
                {{
                  selectedProposal.customer?.name ||
                  selectedProposal.deal?.title
                }}<span v-if="selectedProposal.conversation">
                  • Conversa #{{ selectedProposal.conversation.display_id }} •
                  {{ selectedProposal.conversation.inbox_name }}</span
                >
              </p>
            </div>
            <div class="flex flex-wrap justify-end gap-2">
              <button
                type="button"
                class="rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2 text-sm font-semibold shadow-sm"
                @click="previewProposal"
              >
                <i class="i-lucide-eye mr-1" /> Visualizar
              </button>
              <button
                type="button"
                class="rounded-xl bg-n-ruby-9 px-3 py-2 text-sm font-semibold text-white shadow-sm"
                :disabled="pdfLoading || loadingDetails || saving || itemSaving"
                @click="downloadPdf()"
              >
                <i class="i-lucide-file-text mr-1" />
                {{
                  pdfLoading
                    ? t('CRM.PROPOSAL_PDF.LOADING')
                    : t('CRM.PROPOSAL_PDF.DOWNLOAD')
                }}
              </button>
              <button
                type="button"
                class="rounded-xl bg-n-teal-9 px-3 py-2 text-sm font-semibold text-white shadow-sm"
                @click="copyPublicLink"
              >
                <i class="i-lucide-link mr-1" /> Copiar link
              </button>
              <button
                v-if="
                  !selectedProposal.locked &&
                  selectedProposal.approval?.status !== 'pending'
                "
                type="button"
                class="rounded-xl bg-n-amber-9 px-3 py-2 text-sm font-semibold text-white shadow-sm disabled:opacity-50"
                :disabled="Boolean(actionWorking)"
                @click="requestApproval"
              >
                <i class="i-lucide-shield-check mr-1" /> Solicitar aprovação
              </button>
              <button
                type="button"
                class="rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2 text-sm font-semibold shadow-sm disabled:opacity-50"
                :disabled="Boolean(actionWorking)"
                @click="duplicateProposal"
              >
                <i class="i-lucide-copy-plus mr-1" /> Duplicar
              </button>
              <button
                type="button"
                class="rounded-xl bg-[#16a765] px-3 py-2 text-sm font-semibold text-white shadow-sm disabled:opacity-50"
                :disabled="
                  Boolean(sendingChannel) ||
                  selectedProposal.status === 'accepted' ||
                  selectedProposal.status === 'canceled'
                "
                @click="sendProposal('whatsapp')"
              >
                <i class="i-lucide-message-circle mr-1" />
                {{
                  sendingChannel === 'whatsapp'
                    ? 'Enviando…'
                    : 'Enviar WhatsApp'
                }}
              </button>
              <button
                type="button"
                class="rounded-xl bg-n-brand px-3 py-2 text-sm font-semibold text-white shadow-sm disabled:opacity-50"
                :disabled="
                  Boolean(sendingChannel) ||
                  selectedProposal.status === 'accepted' ||
                  selectedProposal.status === 'canceled'
                "
                @click="sendProposal('email')"
              >
                <i class="i-lucide-mail mr-1" />
                {{ sendingChannel === 'email' ? 'Enviando…' : 'Enviar e-mail' }}
              </button>
              <button
                type="button"
                class="flex size-9 items-center justify-center rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-10 shadow-sm"
                aria-label="Fechar"
                @click="closeProposal"
              >
                <i class="i-lucide-x size-5" />
              </button>
            </div>
          </div>
        </div>

        <p
          v-if="hasUnsavedChanges || hasPendingItem || itemUpdateFailed"
          role="status"
          class="shrink-0 bg-n-amber-3 px-5 py-2 text-sm text-n-amber-11"
        >
          {{ t('CRM.PROPOSAL_PDF.UNSAVED') }}
        </p>
        <div class="shrink-0 border-b border-n-weak bg-n-solid-2 px-5 py-3">
          <ol class="grid grid-cols-2 gap-2 sm:grid-cols-5">
            <li
              v-for="(step, index) in proposalProgress"
              :key="step.label"
              class="flex items-center gap-2"
            >
              <span
                class="flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-bold"
                :class="
                  step.complete
                    ? 'bg-n-teal-9 text-white'
                    : 'bg-n-alpha-3 text-n-slate-9'
                "
              >
                <i v-if="step.complete" class="i-lucide-check size-3.5" />
                <span v-else>{{ index + 1 }}</span>
              </span>
              <span
                class="text-sm font-medium"
                :class="step.complete ? 'text-n-slate-12' : 'text-n-slate-9'"
                >{{ step.label }}</span
              >
              <span
                v-if="index < proposalProgress.length - 1"
                class="hidden h-px flex-1 bg-n-weak sm:block"
              />
            </li>
          </ol>
        </div>

        <div
          v-if="loadingDetails"
          class="m-6 rounded-2xl border border-n-weak bg-n-solid-2 p-8 text-center text-n-slate-10 shadow-sm"
        >
          Carregando proposta…
        </div>
        <div
          v-else
          class="grid min-h-0 flex-1 gap-5 overflow-auto p-5 xl:grid-cols-[minmax(0,1fr)_340px]"
        >
          <div
            class="grid gap-3 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm sm:grid-cols-2 lg:grid-cols-4 xl:col-span-2 xl:grid-cols-7"
          >
            <div>
              <p class="text-xs text-n-slate-10">Status</p>
              <CrmStatusBadge class="mt-1" :value="selectedProposal.status" />
            </div>
            <div>
              <p class="text-xs text-n-slate-10">Implantação</p>
              <CrmValueDisplay
                class="mt-1 font-semibold text-n-blue-11"
                :cents="selectedProposal.implementation_cents"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10">Mensalidade</p>
              <CrmValueDisplay
                class="mt-1 font-semibold text-n-iris-11"
                :cents="selectedProposal.monthly_cents"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10">Descontos</p>
              <CrmValueDisplay
                class="mt-1 font-semibold text-n-amber-11"
                :cents="selectedProposal.total_discount_cents"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10">Total no primeiro mês</p>
              <CrmValueDisplay
                class="mt-1 font-bold text-n-teal-11"
                :cents="selectedProposal.total_first_month_cents"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10">Recorrência mensal</p>
              <CrmValueDisplay
                class="mt-1 font-semibold text-n-teal-11"
                :cents="selectedProposal.recurring_monthly_cents"
              />
            </div>
            <div>
              <p class="text-xs text-n-slate-10">Acompanhamento</p>
              <p class="mt-1 text-sm font-semibold text-n-slate-12">
                {{ selectedProposal.viewed_count || 0 }} visualizações
              </p>
              <p class="text-xs text-n-slate-10">
                Válida até
                {{ selectedProposal.valid_until_display || 'não definida' }}
              </p>
            </div>
          </div>

          <form
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm xl:col-start-1 xl:row-start-2"
            @submit.prevent="saveCommercialData"
          >
            <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
              <div>
                <h4 class="font-bold text-n-slate-12">
                  Conteúdo e condições comerciais
                </h4>
                <p class="text-xs text-n-slate-10">
                  Dados usados na visualização, no PDF, no envio e no aceite
                  digital.
                </p>
              </div>
              <button
                :disabled="saving || selectedProposal.locked"
                class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                <i class="i-lucide-save mr-1" /> Salvar alterações
              </button>
            </div>

            <div
              v-if="selectedProposal.locked"
              class="mb-4 rounded-xl border border-n-amber-6 bg-n-amber-2 p-3 text-sm font-medium text-n-amber-11"
            >
              <i class="i-lucide-lock-keyhole mr-1" /> Esta proposta foi aceita
              e está bloqueada. Use “Duplicar” para criar uma nova versão
              editável.
            </div>

            <fieldset
              :disabled="selectedProposal.locked || itemSaving"
              class="space-y-6 disabled:opacity-70"
            >
              <section>
                <h5 class="mb-3 text-sm font-bold text-n-slate-12">
                  Identificação e conteúdo
                </h5>
                <div class="grid gap-4 md:grid-cols-2">
                  <label
                    class="text-sm font-medium text-n-slate-11 md:col-span-2"
                  >
                    Título
                    <input
                      v-model="proposalForm.title"
                      :disabled="selectedProposal.locked || itemSaving"
                      required
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label
                    class="text-sm font-medium text-n-slate-11 md:col-span-2"
                  >
                    Descrição da solução
                    <textarea
                      v-model="proposalForm.solution_description"
                      :disabled="selectedProposal.locked || itemSaving"
                      rows="4"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Mensalidade (R$)
                    <input
                      v-model="proposalForm.monthly"
                      type="number"
                      min="0"
                      step="0.01"
                      :readonly="selectedProposal.items_count > 0"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2 read-only:bg-n-alpha-2"
                    />
                    <span
                      v-if="selectedProposal.items_count > 0"
                      class="mt-1 block text-xs text-n-slate-9"
                    >
                      Calculada automaticamente pelos itens recorrentes.
                    </span>
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Implantação (R$)
                    <input
                      v-model="proposalForm.implementation"
                      type="number"
                      min="0"
                      step="0.01"
                      :readonly="selectedProposal.items_count > 0"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2 read-only:bg-n-alpha-2"
                    />
                    <span
                      v-if="selectedProposal.items_count > 0"
                      class="mt-1 block text-xs text-n-slate-9"
                    >
                      Calculada automaticamente pelos itens e setups.
                    </span>
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Validade
                    <input
                      v-model="proposalForm.valid_until"
                      :disabled="selectedProposal.locked || itemSaving"
                      type="date"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Vigência (meses)
                    <input
                      v-model.number="proposalForm.term_months"
                      type="number"
                      min="1"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label
                    class="text-sm font-medium text-n-slate-11 md:col-span-2"
                  >
                    Observações comerciais
                    <textarea
                      v-model="proposalForm.commercial_notes"
                      :disabled="selectedProposal.locked || itemSaving"
                      rows="4"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label
                    class="text-sm font-medium text-n-slate-11 md:col-span-2"
                  >
                    Próximos passos
                    <textarea
                      v-model="proposalForm.next_steps"
                      :disabled="selectedProposal.locked || itemSaving"
                      rows="5"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                </div>
              </section>

              <section class="border-t border-n-weak pt-5">
                <h5 class="mb-3 text-sm font-bold text-n-slate-12">
                  Empresa emissora e faturamento
                </h5>
                <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                  <label class="text-sm font-medium text-n-slate-11">
                    Empresa emissora
                    <input
                      v-model="proposalForm.issuer_company_name"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    CNPJ da emissora
                    <input
                      v-model="proposalForm.issuer_tax_id"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                      placeholder="00.000.000/0000-00"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Unidade JRC
                    <input
                      v-model="proposalForm.issuer_unit"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Forma de pagamento
                    <select
                      v-model="proposalForm.payment_method"
                      class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
                    >
                      <option value="">Definir depois</option>
                      <option value="boleto">Boleto</option>
                      <option value="pix">PIX</option>
                      <option value="transferencia">Transferência</option>
                      <option value="cartao">Cartão</option>
                    </select>
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Dia do vencimento
                    <input
                      v-model.number="proposalForm.billing_day"
                      type="number"
                      min="1"
                      max="31"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Primeiro faturamento após (dias)
                    <input
                      v-model.number="proposalForm.first_billing_days"
                      type="number"
                      min="0"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Índice de reajuste anual
                    <input
                      v-model="proposalForm.annual_adjustment_index"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                      placeholder="IPCA"
                    />
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Renovação
                    <select
                      v-model="proposalForm.renewal_type"
                      class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2"
                    >
                      <option value="automatic">Automática</option>
                      <option value="manual">Manual</option>
                      <option value="none">Sem renovação</option>
                    </select>
                  </label>
                  <label class="text-sm font-medium text-n-slate-11">
                    Multa de cancelamento (%)
                    <input
                      v-model.number="proposalForm.cancellation_penalty_percent"
                      type="number"
                      min="0"
                      max="100"
                      step="0.01"
                      class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                    />
                  </label>
                </div>
                <div class="mt-4 grid gap-3 sm:grid-cols-2">
                  <label
                    class="flex items-center justify-between gap-3 rounded-xl border border-n-weak p-3"
                  >
                    <span>
                      <span class="block text-sm font-semibold text-n-slate-12"
                        >Impostos inclusos</span
                      >
                      <span class="text-xs text-n-slate-10"
                        >Indica como os valores serão apresentados.</span
                      >
                    </span>
                    <input
                      v-model="proposalForm.taxes_included"
                      type="checkbox"
                      class="size-5 accent-n-teal-9"
                    />
                  </label>
                  <label
                    class="flex items-center justify-between gap-3 rounded-xl border border-n-weak p-3"
                  >
                    <span>
                      <span class="block text-sm font-semibold text-n-slate-12"
                        >Acompanhamento automático</span
                      >
                      <span class="text-xs text-n-slate-10"
                        >Registrar lembrete após o envio.</span
                      >
                    </span>
                    <input
                      v-model="proposalForm.follow_up_enabled"
                      type="checkbox"
                      class="size-5 accent-n-iris-9"
                    />
                  </label>
                </div>
                <label
                  v-if="proposalForm.follow_up_enabled"
                  class="mt-4 block text-sm font-medium text-n-slate-11"
                >
                  Acompanhamento após (dias)
                  <input
                    v-model.number="proposalForm.follow_up_days"
                    type="number"
                    min="0"
                    class="mt-1 w-full max-w-xs rounded-lg border border-n-weak px-3 py-2"
                  />
                </label>
              </section>
            </fieldset>
          </form>

          <div
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm xl:col-start-1 xl:row-start-3"
          >
            <div class="mb-4">
              <h4 class="font-bold text-n-slate-12">Produtos e descontos</h4>
              <p class="text-xs text-n-slate-10">
                Os produtos do negócio entram automaticamente; você pode ajustar
                quantidade, preço e desconto antes do envio.
              </p>
            </div>
            <form
              v-if="!selectedProposal.locked"
              class="grid gap-3 md:grid-cols-[1fr_110px_140px_auto]"
              @submit.prevent="addItem"
            >
              <select
                v-model="itemForm.product_id"
                :disabled="selectedProposal.locked || itemSaving"
                required
                class="rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm"
                @change="selectProduct"
              >
                <option disabled value="">Adicionar produto</option>
                <option
                  v-for="product in products"
                  :key="product.id"
                  :value="product.id"
                >
                  {{ product.name }} {{ product.sku ? `(${product.sku})` : '' }}
                </option>
              </select>
              <input
                v-model.number="itemForm.quantity"
                :disabled="selectedProposal.locked || itemSaving"
                min="1"
                required
                type="number"
                class="rounded-lg border border-n-weak px-3 py-2 text-sm"
                placeholder="Qtd"
              />
              <input
                v-model="itemForm.unit_price"
                :disabled="selectedProposal.locked || itemSaving"
                min="0"
                step="0.01"
                required
                type="number"
                class="rounded-lg border border-n-weak px-3 py-2 text-sm"
                placeholder="Preço"
              />
              <button
                type="submit"
                :disabled="itemSaving || selectedProposal.locked"
                class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                + Adicionar
              </button>
            </form>

            <div class="mt-4 overflow-auto rounded-xl border border-n-weak">
              <table class="min-w-full divide-y divide-n-weak text-sm">
                <thead
                  class="bg-n-alpha-2 text-left text-xs uppercase text-n-slate-10"
                >
                  <tr>
                    <th class="px-4 py-3">Produto</th>
                    <th class="px-4 py-3 text-right">Qtd</th>
                    <th class="px-4 py-3 text-right">Preço unitário</th>
                    <th class="px-4 py-3 text-right">Desconto</th>
                    <th class="px-4 py-3 text-right">Total no primeiro mês</th>
                    <th class="px-4 py-3" />
                  </tr>
                </thead>
                <tbody class="divide-y divide-n-weak">
                  <tr v-if="!selectedProposal.items?.length">
                    <td
                      colspan="6"
                      class="px-4 py-8 text-center text-n-slate-10"
                    >
                      Nenhum produto adicionado.
                    </td>
                  </tr>
                  <tr v-for="item in selectedProposal.items" :key="item.id">
                    <td class="px-4 py-3">
                      <p class="font-medium text-n-slate-12">
                        {{ item.name_snapshot }}
                      </p>
                      <p
                        v-if="item.product?.sku"
                        class="text-xs text-n-slate-10"
                      >
                        SKU {{ item.product.sku }}
                      </p>
                      <div class="mt-2 flex flex-wrap gap-1 text-[11px]">
                        <span
                          class="rounded-full bg-n-iris-3 px-2 py-0.5 text-n-iris-11"
                        >
                          {{ billingLabel(item.billing_model) }}
                        </span>
                        <span
                          v-if="item.setup_fee_cents"
                          class="rounded-full bg-n-blue-3 px-2 py-0.5 text-n-blue-11"
                        >
                          Implantação
                          <CrmValueDisplay :cents="item.setup_fee_cents" />
                        </span>
                        <span
                          v-if="item.included_quantity"
                          class="rounded-full bg-n-teal-3 px-2 py-0.5 text-n-teal-11"
                        >
                          {{ item.included_quantity }}
                          {{ item.included_unit || 'incluídos' }}
                        </span>
                      </div>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <input
                        v-model.number="item.quantity"
                        min="1"
                        type="number"
                        class="w-20 rounded border border-n-weak px-2 py-1 text-right"
                        :disabled="selectedProposal.locked || itemSaving"
                        @change="updateItem(item)"
                      />
                    </td>
                    <td class="px-4 py-3 text-right">
                      <input
                        :value="moneyInput(item.unit_price_cents)"
                        min="0"
                        step="0.01"
                        type="number"
                        class="w-28 rounded border border-n-weak px-2 py-1 text-right"
                        :disabled="selectedProposal.locked || itemSaving"
                        @change="updateItemPrice(item, $event.target.value)"
                      />
                    </td>
                    <td class="px-4 py-3 text-right">
                      <input
                        :value="moneyInput(item.discount_cents)"
                        min="0"
                        step="0.01"
                        type="number"
                        class="w-24 rounded border border-n-weak px-2 py-1 text-right"
                        :disabled="selectedProposal.locked || itemSaving"
                        @change="updateItemDiscount(item, $event.target.value)"
                      />
                    </td>
                    <td class="px-4 py-3 text-right font-semibold">
                      <CrmValueDisplay :cents="item.initial_total_cents" />
                      <p
                        v-if="item.recurring_total_cents"
                        class="mt-1 text-xs font-normal text-n-teal-11"
                      >
                        Recorrência
                        <CrmValueDisplay :cents="item.recurring_total_cents" />
                      </p>
                    </td>
                    <td class="px-4 py-3 text-right">
                      <button
                        v-if="!selectedProposal.locked"
                        type="button"
                        class="rounded-lg border border-n-weak px-3 py-1.5 text-xs text-n-ruby-11 disabled:opacity-40"
                        :disabled="selectedProposal.locked || itemSaving"
                        @click="removeItem(item)"
                      >
                        Remover
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div
              class="ml-auto mt-4 grid w-full max-w-sm gap-2 rounded-xl bg-n-alpha-2 p-4"
            >
              <label class="text-sm font-medium text-n-slate-11"
                >Desconto comercial adicional (R$)</label
              ><input
                v-model="proposalDiscount"
                type="number"
                min="0"
                step="0.01"
                class="rounded-lg border border-n-weak px-3 py-2"
                :disabled="selectedProposal.locked || itemSaving"
              />
              <p class="text-xs text-n-slate-10">
                Aplicado depois dos descontos individuais dos produtos. Clique
                em Salvar no bloco comercial antes do envio.
              </p>
            </div>
          </div>

          <div
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm xl:col-start-2 xl:row-start-2"
          >
            <h4 class="font-bold text-n-slate-12">Resumo e entrega</h4>
            <div class="mt-4 space-y-4 text-sm">
              <div>
                <p class="text-xs text-n-slate-10">Cliente</p>
                <p class="mt-1 font-semibold">
                  {{
                    selectedProposal.customer?.name || 'Sem cliente vinculado'
                  }}
                </p>
              </div>
              <div>
                <p class="text-xs text-n-slate-10">WhatsApp / telefone</p>
                <p class="mt-1 font-semibold">
                  {{
                    selectedProposal.customer?.phone_number || 'Não cadastrado'
                  }}
                </p>
              </div>
              <div>
                <p class="text-xs text-n-slate-10">E-mail</p>
                <p class="mt-1 break-all font-semibold">
                  {{ selectedProposal.customer?.email || 'Não cadastrado' }}
                </p>
              </div>
              <div class="border-t border-n-weak pt-4">
                <p class="text-xs text-n-slate-10">Total no primeiro mês</p>
                <CrmValueDisplay
                  class="mt-1 text-xl font-bold text-n-teal-11"
                  :cents="selectedProposal.total_first_month_cents"
                />
                <p class="mt-2 text-xs text-n-slate-10">Recorrência mensal</p>
                <CrmValueDisplay
                  class="mt-1 font-semibold text-n-teal-11"
                  :cents="selectedProposal.recurring_monthly_cents"
                />
              </div>
            </div>
            <p class="mt-4 text-xs leading-5 text-n-slate-10">
              O envio usa primeiro a conversa já vinculada ao negócio. Se o
              canal escolhido não for o da conversa vinculada, o sistema procura
              outra conversa existente do mesmo cliente nesse canal. O envio
              fica registrado na conversa e na timeline do CRM.
            </p>
            <p
              v-if="selectedProposal.viewed_at_display"
              class="mt-3 rounded-xl bg-n-teal-3 p-3 text-sm font-semibold text-n-teal-11"
            >
              Visualizada em {{ selectedProposal.viewed_at_display }}
            </p>
          </div>

          <div
            class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm xl:col-start-2 xl:row-start-3"
          >
            <div class="flex items-center justify-between gap-3">
              <div>
                <h4 class="font-bold text-n-slate-12">Aprovação interna</h4>
                <p class="text-xs text-n-slate-10">
                  Comercial, financeiro e técnico antes do envio.
                </p>
              </div>
              <span
                class="rounded-full bg-n-amber-3 px-2.5 py-1 text-xs font-semibold text-n-amber-11"
              >
                {{
                  selectedProposal.approval?.status_display || 'Não requerida'
                }}
              </span>
            </div>

            <div class="mt-4 space-y-3">
              <div
                v-for="approvalItem in [
                  { key: 'commercial', label: 'Comercial' },
                  { key: 'financial', label: 'Financeira' },
                  { key: 'technical', label: 'Técnica' },
                ]"
                :key="approvalItem.key"
                class="rounded-xl border border-n-weak p-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <span class="text-sm font-semibold text-n-slate-12">{{
                    approvalItem.label
                  }}</span>
                  <span
                    class="rounded-full px-2 py-0.5 text-xs font-semibold"
                    :class="
                      selectedProposal.approval?.[approvalItem.key] ===
                      'approved'
                        ? 'bg-n-teal-3 text-n-teal-11'
                        : selectedProposal.approval?.[approvalItem.key] ===
                            'rejected'
                          ? 'bg-n-ruby-3 text-n-ruby-11'
                          : selectedProposal.approval?.[approvalItem.key] ===
                              'pending'
                            ? 'bg-n-amber-3 text-n-amber-11'
                            : 'bg-n-alpha-3 text-n-slate-10'
                    "
                  >
                    {{
                      selectedProposal.approval?.[
                        `${approvalItem.key}_display`
                      ] || 'Não requerida'
                    }}
                  </span>
                </div>
                <div
                  v-if="
                    isAdmin &&
                    selectedProposal.approval?.[approvalItem.key] === 'pending'
                  "
                  class="mt-3 flex gap-2"
                >
                  <button
                    type="button"
                    class="flex-1 rounded-lg bg-n-teal-9 px-3 py-2 text-xs font-semibold text-white disabled:opacity-50"
                    :disabled="Boolean(actionWorking)"
                    @click="updateApproval(approvalItem.key, 'approved')"
                  >
                    Aprovar
                  </button>
                  <button
                    type="button"
                    class="flex-1 rounded-lg border border-n-ruby-7 px-3 py-2 text-xs font-semibold text-n-ruby-11 disabled:opacity-50"
                    :disabled="Boolean(actionWorking)"
                    @click="updateApproval(approvalItem.key, 'rejected')"
                  >
                    Reprovar
                  </button>
                </div>
              </div>
            </div>

            <div
              v-if="selectedProposal.acceptance?.name"
              class="mt-4 rounded-xl bg-n-teal-2 p-3"
            >
              <p class="text-xs font-semibold uppercase text-n-teal-11">
                Aceite digital
              </p>
              <p class="mt-1 text-sm font-semibold text-n-slate-12">
                {{ selectedProposal.acceptance.name }}
              </p>
              <p class="text-xs text-n-slate-10">
                Documento {{ selectedProposal.acceptance.document }} ·
                {{ selectedProposal.acceptance.accepted_at_display }}
              </p>
            </div>
          </div>
        </div>
      </aside>
    </div>
  </div>
</template>
