<script setup>
/* eslint-disable vue/no-bare-strings-in-template */
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useFormDraft } from '../../helpers/useFormDraft';
import { useStore } from 'vuex';
import {
  proposalToOrderForm,
  orderFinancialPayload,
} from '../../helpers/commercialTerms';
import AgentsAPI from 'dashboard/api/agents';
import {
  contractsAPI,
  salesOrdersAPI,
} from 'dashboard/api/crm/commercialCycle';
import productsAPI from 'dashboard/api/crm/products';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const route = useRoute();
const router = useRouter();
const store = useStore();
const step = ref(1);
const saving = ref(false);
const products = ref([]);
const proposals = ref([]);
const deals = ref([]);
const contacts = ref([]);
const agents = ref([]);
const search = ref('');
const customerQuery = ref('');
const dealQuery = ref('');
const selectionLoading = ref(false);
const proposalState = ref({
  message: 'Selecione um negócio para consultar propostas.',
  counts: {},
  attention_proposal: null,
});
let customerTimer;
let dealTimer;
const steps = [
  ['Dados principais', 'Cliente e informações'],
  ['Itens', 'Produtos e serviços'],
  ['Financeiro', 'Valores e condições'],
  ['Operação', 'Implantação e entrega'],
  ['Revisão', 'Confira e finalize'],
];
const form = reactive({
  customer_name: '',
  contact_id: null,
  deal_id: null,
  proposal_id: null,
  owner_id: null,
  order_origin: 'direct_sale',
  order_type: 'Venda de produtos e serviços',
  order_date: new Date().toISOString().slice(0, 10),
  activation_date: '',
  notes: '',
  items: [],
  payment_method: 'boleto',
  payment_condition: 'installments',
  installments_count: 1,
  first_due_date: '',
  down_payment_cents: 0,
  shipping_cents: 0,
  shipping_mode: 'not_applicable',
  shipping_in_installments: true,
  has_monthly_fee: true,
  general_discount_cents: null,
  discount_percent: 0,
  taxes_percent: 0,
  cost_center: 'Comercial',
  financial_notes: '',
  operation_owner_name: '',
  customer_owner_name: '',
  implementation_team: 'Time de Implantação',
  priority: 'Normal',
  operation_notes: '',
  send_confirmation: false,
  send_schedule: false,
  notify_steps: false,
  email_template: 'Confirmação de pedido + cronograma',
  generate_contract: false,
  send_to_implementation: false,
  create_implementation_project: false,
  create_follow_up: false,
  follow_up_due_at: '',
  tags: '',
  proposal_version: null,
  term_months: null,
  renewal_type: '',
  billing_day: null,
  annual_adjustment_index: '',
  cancellation_penalty_percent: null,
  commercial_notes: '',
  next_steps: '',
  customer_notes: '',
  documents: [],
  checklist: [
    { label: 'Confirmar dados do cliente', done: true },
    { label: 'Verificar pré-requisitos técnicos', done: true },
    { label: 'Provisionar serviços', done: false },
    { label: 'Configurar acessos e usuários', done: false },
    { label: 'Realizar testes de funcionamento', done: false },
    { label: 'Agendar treinamento', done: false },
    { label: 'Entregar ao cliente', done: false },
  ],
});

const orderDraftActive = ref(true);
const initialOrderForm = JSON.parse(JSON.stringify(form));
const orderDraft = useFormDraft('crm:new_order', {
  active: orderDraftActive,
  snapshot: () => ({ form: { ...form, documents: [] }, step: step.value }),
  restore: value => {
    Object.assign(form, value.form || {}, { documents: [] });
    step.value = value.step || 1;
  },
  reset: () => {
    Object.assign(form, JSON.parse(JSON.stringify(initialOrderForm)));
    step.value = 1;
  },
});
const recoveredOrder = orderDraft.open();

const money = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    (Number(value) || 0) / 100
  );
const selectedProposal = computed(() =>
  proposals.value.find(p => String(p.id) === String(form.proposal_id))
);
const selectedDeal = computed(() =>
  deals.value.find(d => String(d.id) === String(form.deal_id))
);
const selectedContact = computed(
  () =>
    contacts.value.find(c => String(c.id) === String(form.contact_id)) ||
    selectedProposal.value?.customer ||
    selectedDeal.value?.contact
);
const contactLabel = c =>
  [
    c?.name || c?.email || c?.phone_number || `#${c?.id}`,
    c?.company_name || c?.trade_name,
    c?.phone_number,
    c?.customer_code,
  ]
    .filter(Boolean)
    .join(' | ');
const dealLabel = d =>
  `${d?.title || ''} | ${d?.company_name || d?.contact?.company_name || d?.contact?.name || 'Cliente'} | ${money(d?.value_cents)} | ${d?.stage?.name || d?.status || ''}`;
const filteredDeals = computed(() =>
  deals.value.filter(
    d =>
      !dealQuery.value ||
      dealLabel(d).toLowerCase().includes(dealQuery.value.toLowerCase())
  )
);
const filteredProducts = computed(() =>
  products.value.filter(
    p =>
      !search.value ||
      `${p.name} ${p.category || ''}`
        .toLowerCase()
        .includes(search.value.toLowerCase())
  )
);
const financials = ref({
  products_cents: 0,
  discount_cents: 0,
  taxes_cents: 0,
  total_cents: 0,
  monthly_cents: 0,
  installments: [],
});
const calculating = ref(false);
const calculationError = ref('');
let previewSequence = 0;
const financialInput = computed(() => orderFinancialPayload(form));
const refreshFinancials = async () => {
  previewSequence += 1;
  const sequence = previewSequence;
  calculating.value = true;
  calculationError.value = '';
  try {
    const { data } = await salesOrdersAPI.preview({
      sales_order: financialInput.value,
    });
    if (sequence !== previewSequence) return false;
    financials.value = data;
    data.items.forEach(
      (item, index) =>
        form.items[index] &&
        Object.assign(form.items[index], {
          one_time_cents: item.one_time_cents,
          recurring_cents: item.recurring_cents,
          discount_cents: item.discount_cents,
        })
    );
    return true;
  } catch (error) {
    if (sequence === previewSequence)
      calculationError.value =
        error.response?.data?.errors?.join(', ') ||
        error.response?.data?.message ||
        t('CRM.WORKFLOW_UI.CALCULATION_ERROR');
    return false;
  } finally {
    if (sequence === previewSequence) calculating.value = false;
  }
};
watch(financialInput, refreshFinancials, { deep: true });
const subtotal = computed(() => financials.value.products_cents);
const discount = computed(() => financials.value.discount_cents);
const taxes = computed(() => financials.value.taxes_cents);
const total = computed(() => financials.value.total_cents);
const monthly = computed(() => financials.value.monthly_cents);
const ticket = computed(() =>
  form.items.length ? Math.round(total.value / form.items.length) : 0
);
const installmentRows = computed(() => financials.value.installments);
const recalc = item => {
  if (item) item.discount_mode = 'percent';
  return refreshFinancials();
};
const addProduct = product => {
  const existing = form.items.find(i => i.product_id === product.id);
  if (existing) {
    existing.quantity += 1;
    recalc(existing);
    return;
  }
  const item = {
    product_id: product.id,
    name: product.name,
    description: product.description || '',
    quantity: 1,
    unit_cents: Number(product.unit_price_cents || 0),
    discount_percent: 0,
    one_time_cents: 0,
    recurring_cents: 0,
    snapshot: {
      category: product.category,
      product_type: product.product_type,
      billing_model: product.billing_model,
      unit_name: product.sales_unit,
      setup_fee_cents: Number(product.setup_fee_cents || 0),
      implementation_type:
        product.product_type === 'service' ? 'Assistida' : 'Automática',
      implementation_owner: '',
      implementation_date: form.activation_date,
      status: 'Pendente',
      implementation_notes: '',
    },
  };
  form.items.push(item);
};
const removeItem = index => form.items.splice(index, 1);
const hydrateProposal = proposal => {
  if (!proposal || proposal.status !== 'accepted') return;
  Object.assign(form, proposalToOrderForm(proposal));
  form.proposal_id = proposal.id;
  form.proposal_version = proposal.version_number;
  form.order_origin = 'proposal_deal';
  form.term_months = proposal.term_months || null;
  form.renewal_type = proposal.payment?.renewal_type || '';
  form.commercial_notes = proposal.commercial_notes || '';
};
const importProposal = () => hydrateProposal(selectedProposal.value);
const applySelectionResponse = data => {
  if (data.selected_contact) {
    contacts.value = [data.selected_contact];
    form.contact_id = data.selected_contact.id;
    form.customer_name =
      data.selected_contact.name || data.selected_contact.company_name || '';
    customerQuery.value = contactLabel(data.selected_contact);
  }
  if (data.selected_deal) {
    deals.value = [
      data.selected_deal,
      ...(data.deals || []).filter(
        d => String(d.id) !== String(data.selected_deal.id)
      ),
    ];
    form.deal_id = data.selected_deal.id;
    form.owner_id = data.selected_deal.owner?.id || form.owner_id;
    dealQuery.value = dealLabel(data.selected_deal);
  } else if (data.deals) deals.value = data.deals;
  proposals.value = data.proposals || [];
  proposalState.value = data.proposal_state || proposalState.value;
  if (data.selected_proposal?.status === 'accepted') {
    proposals.value = [
      data.selected_proposal,
      ...proposals.value.filter(
        p => String(p.id) !== String(data.selected_proposal.id)
      ),
    ];
    hydrateProposal(data.selected_proposal);
  }
};
const fetchSelection = async params => {
  selectionLoading.value = true;
  try {
    const { data } = await salesOrdersAPI.selectionOptions(params);
    applySelectionResponse(data);
    return data;
  } finally {
    selectionLoading.value = false;
  }
};
const searchCustomers = () => {
  clearTimeout(customerTimer);
  if (
    form.contact_id &&
    customerQuery.value === contactLabel(selectedContact.value)
  )
    return;
  if (customerQuery.value.trim().length < 2) {
    contacts.value = [];
    return;
  }
  customerTimer = setTimeout(async () => {
    try {
      const { data } = await salesOrdersAPI.selectionOptions({
        customer_q: customerQuery.value.trim(),
      });
      contacts.value = data.contacts || [];
    } catch (e) {
      useAlert('Não foi possível pesquisar clientes.');
    }
  }, 300);
};
const chooseContact = async c => {
  const changed = String(form.contact_id || '') !== String(c.id);
  const hadProposal = !!form.proposal_id;
  contacts.value = [c];
  form.contact_id = c.id;
  form.customer_name = c.name || c.company_name || '';
  customerQuery.value = contactLabel(c);
  if (changed) {
    form.deal_id = null;
    form.proposal_id = null;
    form.proposal_version = null;
    deals.value = [];
    proposals.value = [];
    dealQuery.value = '';
    if (hadProposal) form.items = [];
  }
  await fetchSelection({ contact_id: c.id });
};
const clearContact = () => {
  form.contact_id = null;
  form.customer_name = '';
  customerQuery.value = '';
  form.deal_id = null;
  form.proposal_id = null;
  form.proposal_version = null;
  form.items = [];
  deals.value = [];
  proposals.value = [];
  dealQuery.value = '';
  proposalState.value = {
    message: 'Selecione um negócio para consultar propostas.',
    counts: {},
    attention_proposal: null,
  };
};
const searchDeals = () => {
  clearTimeout(dealTimer);
  if (form.contact_id) return;
  if (dealQuery.value.trim().length < 2) {
    deals.value = [];
    return;
  }
  dealTimer = setTimeout(
    () => fetchSelection({ deal_q: dealQuery.value.trim() }),
    300
  );
};
const chooseDeal = async d => {
  const hadProposal = !!form.proposal_id;
  form.deal_id = d.id;
  form.proposal_id = null;
  form.proposal_version = null;
  if (hadProposal) form.items = [];
  form.order_origin = 'proposal_deal';
  dealQuery.value = dealLabel(d);
  const data = await fetchSelection({ deal_id: d.id });
  if (data.selected_contact) form.contact_id = data.selected_contact.id;
};
const clearDeal = () => {
  form.deal_id = null;
  form.proposal_id = null;
  form.proposal_version = null;
  form.items = [];
  proposals.value = [];
  dealQuery.value = '';
  if (form.order_origin === 'proposal_deal') form.order_origin = 'direct_sale';
  proposalState.value = {
    message: 'Selecione um negócio para consultar propostas.',
    counts: {},
    attention_proposal: null,
  };
};
const chooseProposal = async p => {
  if (p.status !== 'accepted') return;
  const data = await fetchSelection({ proposal_id: p.id });
  if (data.selected_proposal?.status === 'accepted')
    hydrateProposal(data.selected_proposal);
};
const clearProposal = () => {
  form.proposal_id = null;
  form.proposal_version = null;
  form.items = [];
  form.general_discount_cents = null;
  form.term_months = null;
  form.renewal_type = '';
  form.commercial_notes = '';
  if (form.deal_id) form.order_origin = 'proposal_deal';
};
const viewAttentionProposal = () => {
  const id = proposalState.value?.attention_proposal?.id;
  if (id)
    router.push({
      name: 'crm_proposals',
      params: { accountId: route.params.accountId },
      query: { proposalId: id },
    });
};
const canNext = computed(() => {
  if (step.value === 1) return !!form.contact_id && !!form.owner_id;
  if (step.value === 2) return form.items.length > 0;
  return true;
});
const next = () => {
  if (!canNext.value) {
    useAlert(
      step.value === 1
        ? 'Selecione o cliente e o responsável.'
        : 'Adicione ao menos um item.'
    );
    return;
  }
  step.value = Math.min(step.value + 1, 5);
};
const go = target => {
  if (target <= step.value) step.value = target;
};
const payload = status => ({
  sales_order: {
    ...financialInput.value,
    contact_id: form.contact_id || null,
    deal_id: form.deal_id || null,
    order_origin: form.order_origin,
    owner_id: form.owner_id || null,
    status,
    sold_at: form.order_date,
    notes: form.notes,
    snapshot: {
      ...financialInput.value.snapshot,
      customer_name: form.customer_name,
      company_name: 'JRC Conversas',
      order_origin: form.order_origin,
      order_type: form.order_type,
      activation_date: form.activation_date,
      cost_center: form.cost_center,
      proposal_version: form.proposal_version,
      term_months: form.term_months,
      renewal_type: form.renewal_type,
      billing_day: form.billing_day,
      annual_adjustment_index: form.annual_adjustment_index,
      cancellation_penalty_percent: form.cancellation_penalty_percent,
      commercial_notes: form.commercial_notes,
      next_steps: form.next_steps,
      customer_notes: form.customer_notes,
      financial_notes: form.financial_notes,
      operation_owner_name: form.operation_owner_name,
      customer_owner_name: form.customer_owner_name,
      implementation_team: form.implementation_team,
      priority: form.priority,
      operation_notes: form.operation_notes,
      send_confirmation: false,
      send_schedule: false,
      notify_steps: false,
      generate_contract: form.generate_contract,
      send_to_implementation: form.send_to_implementation,
      create_implementation_project: Boolean(
        form.send_to_implementation && form.create_implementation_project
      ),
      create_follow_up: Boolean(form.deal_id && form.create_follow_up),
      follow_up_due_at: form.follow_up_due_at,
      tags: form.tags,
      checklist: form.checklist,
      documents: form.documents.map(d => ({
        name: d.name,
        size: d.size,
        type: d.type,
      })),
    },
  },
});
const save = async (status = 'pending') => {
  const savingDraftKey = orderDraft.key.value;
  saving.value = true;
  try {
    if (!form.contact_id) {
      useAlert('Selecione o cliente antes de salvar o pedido.');
      return;
    }
    if (form.proposal_id && selectedProposal.value?.status !== 'accepted') {
      useAlert('Somente proposta aceita pode gerar pedido.');
      return;
    }
    if (
      status !== 'draft' &&
      form.deal_id &&
      form.create_follow_up &&
      !form.follow_up_due_at
    ) {
      useAlert(t('CRM.HOMOLOGATION.FOLLOW_UP_DATE'));
      return;
    }
    if (!(await refreshFinancials())) {
      useAlert(calculationError.value || t('CRM.WORKFLOW_UI.WAIT_CALCULATION'));
      return;
    }
    const { data } = await salesOrdersAPI.create(payload(status));
    if (!orderDraft.complete(savingDraftKey)) return;
    orderDraftActive.value = false;
    const warnings = [];
    if (form.documents.length) {
      try {
        await salesOrdersAPI.uploadAttachments(
          data.id,
          form.documents.map(d => d.file)
        );
      } catch (error) {
        warnings.push(
          'O pedido foi salvo, mas um ou mais anexos não puderam ser enviados.'
        );
      }
    }
    if (status !== 'draft' && form.generate_contract) {
      try {
        await contractsAPI.create({
          contract: {
            sales_order_id: data.id,
            status: 'draft',
            starts_on: form.activation_date || null,
            monthly_cents: monthly.value,
            one_time_cents: total.value,
            notes: `Contrato gerado a partir do pedido ${data.order_number}`,
          },
        });
      } catch (error) {
        warnings.push(
          'O pedido foi salvo, mas o contrato automático não pôde ser criado.'
        );
      }
    }
    if (
      status !== 'draft' &&
      form.send_to_implementation &&
      data.status !== 'approved'
    ) {
      warnings.push(
        'A implantação ficou registrada como solicitada e só poderá avançar após a aprovação do pedido.'
      );
    }
    useAlert(
      [
        status === 'draft'
          ? `Rascunho ${data.order_number} salvo.`
          : `Pedido ${data.order_number} finalizado.`,
        ...warnings,
      ].join(' ')
    );
    router.push({
      name: 'crm_orders',
      params: { accountId: route.params.accountId },
      query: { orderId: data.id },
    });
  } catch (e) {
    useAlert(
      e.response?.data?.errors?.join(', ') ||
        e.response?.data?.message ||
        'Não foi possível criar o pedido.'
    );
  } finally {
    saving.value = false;
  }
};
const addFiles = event => {
  form.documents = [
    ...form.documents,
    ...Array.from(event.target.files || []).map(file => ({
      name: file.name,
      size: file.size,
      type: file.type,
      file,
    })),
  ];
  event.target.value = '';
};
const removeDocument = index => form.documents.splice(index, 1);
watch(
  () => form.activation_date,
  value =>
    form.items.forEach(i => {
      if (!i.snapshot.implementation_date)
        i.snapshot.implementation_date = value;
    })
);
watch(
  () => form.send_to_implementation,
  value => {
    if (!value) form.create_implementation_project = false;
  }
);
watch(
  () => form.order_type,
  value => {
    if (value === 'Renovação') form.order_origin = 'renewal';
    else if (value === 'Upgrade / expansão') form.order_origin = 'expansion';
  }
);

onMounted(async () => {
  const [pr, aa] = await Promise.all([
    productsAPI.list({ active: true }),
    AgentsAPI.get(),
  ]);
  products.value = pr.data || [];
  agents.value = aa.data || [];
  form.owner_id = store.getters.getCurrentUser?.id || null;
  const proposalId = route.query.proposalId;
  const dealId = route.query.dealId;
  const contactId = route.query.contactId;
  if (recoveredOrder && form.proposal_id) {
    const recovered = JSON.parse(JSON.stringify(form));
    await fetchSelection({ proposal_id: form.proposal_id });
    Object.assign(form, recovered);
  } else if (!recoveredOrder && proposalId)
    await fetchSelection({ proposal_id: proposalId });
  else if (!recoveredOrder && dealId) await fetchSelection({ deal_id: dealId });
  else if (!recoveredOrder && contactId)
    await fetchSelection({ contact_id: contactId });
});
</script>

<template>
  <div
    class="h-full overflow-auto bg-n-background dark:bg-n-background p-4 sm:p-6"
  >
    <header class="mb-4 flex flex-wrap items-center justify-between gap-4">
      <button
        type="button"
        class="rounded-lg border border-n-weak px-3 py-2"
        :disabled="saving"
        @click="orderDraft.discard"
      >
        {{ t('CRM.CREATION.DISCARD') }}
      </button>
      <div class="flex gap-3">
        <span
          class="grid size-12 place-content-center rounded-2xl bg-blue-600 text-white shadow-lg shadow-blue-100"
          ><i class="i-lucide-shopping-cart size-6"
        /></span>
        <div>
          <p class="text-xs text-n-slate-11">
            Vendas / Pedidos &nbsp;›&nbsp; Novo pedido
          </p>
          <h2 class="text-2xl font-bold">Novo Pedido</h2>
          <p class="text-sm text-n-slate-11">
            Crie um novo pedido a partir de um cliente, negócio ou proposta.
          </p>
        </div>
      </div>
      <button
        class="rounded-xl border bg-n-solid-2 px-4 py-2.5 font-semibold"
        @click="
          router.push({
            name: 'crm_orders',
            params: { accountId: route.params.accountId },
          })
        "
      >
        ← Voltar para a lista
      </button>
    </header>
    <section
      class="mb-5 grid gap-2 rounded-2xl border bg-n-solid-2 p-4 shadow-sm md:grid-cols-5"
    >
      <button
        v-for="(s, i) in steps"
        :key="s[0]"
        class="flex items-center gap-3 text-left"
        @click="go(i + 1)"
      >
        <b
          class="grid size-9 shrink-0 place-content-center rounded-full"
          :class="
            i + 1 === step
              ? 'bg-blue-600 text-white'
              : i + 1 < step
                ? 'bg-emerald-600 text-white'
                : 'bg-n-slate-3 text-n-slate-12'
          "
          >{{ i + 1 < step ? '✓' : i + 1 }}</b
        ><span
          ><strong class="block text-sm">{{ s[0] }}</strong
          ><small class="text-n-slate-11">{{ s[1] }}</small></span
        >
      </button>
    </section>

    <p v-if="calculating" role="status" class="mb-3 text-sm text-blue-700">
      {{ t('CRM.WORKFLOW_UI.CALCULATING') }}
    </p>
    <p
      v-if="calculationError"
      role="alert"
      class="mb-3 rounded-xl border border-red-300 bg-red-50 p-3 text-red-800"
    >
      {{ calculationError }}
    </p>
    <p
      v-if="selectedProposal"
      class="mb-4 rounded-xl border border-blue-200 bg-blue-50 p-3 text-sm"
    >
      Valores e itens preservados da proposta aceita
      <b
        >{{ selectedProposal.proposal_number }} v{{
          selectedProposal.version_number
        }}</b
      >. Alterações comerciais exigem uma nova versão da proposta.
    </p>
    <section
      v-if="step === 1"
      class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_320px]"
    >
      <div class="space-y-4">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="mb-4 text-lg font-bold">Dados do pedido</h3>
          <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            <label class="relative"
              >Cliente *
              <div class="mt-1 flex gap-2">
                <input
                  v-model="customerQuery"
                  :disabled="!!selectedProposal"
                  class="w-full rounded-xl border p-2.5"
                  placeholder="Nome, empresa, telefone, e-mail, CPF/CNPJ ou código"
                  @input="searchCustomers"
                /><button
                  v-if="form.contact_id && !selectedProposal"
                  type="button"
                  class="rounded-xl border px-3"
                  @click="clearContact"
                >
                  ✕
                </button>
              </div>
              <div
                v-if="!form.contact_id && contacts.length"
                class="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-xl border bg-n-solid-2 p-1 shadow-xl"
              >
                <button
                  v-for="c in contacts"
                  :key="c.id"
                  type="button"
                  class="block w-full rounded-lg px-3 py-2 text-left hover:bg-n-slate-2"
                  @click="chooseContact(c)"
                >
                  <b>{{ c.name || c.email || c.phone_number }}</b
                  ><small class="block text-n-slate-11">{{
                    [
                      c.company_name || c.trade_name,
                      c.phone_number,
                      c.email,
                      c.customer_code,
                    ]
                      .filter(Boolean)
                      .join(' · ')
                  }}</small>
                </button>
              </div>
              <small v-if="selectionLoading" class="text-blue-700">
                Consultando vínculos…
              </small>
            </label>
            <label class="relative"
              >Negócio (opcional)
              <div class="mt-1 flex gap-2">
                <input
                  v-model="dealQuery"
                  :disabled="!!selectedProposal"
                  class="w-full rounded-xl border p-2.5"
                  placeholder="Selecione o cliente ou pesquise o negócio"
                  @focus="
                    form.contact_id &&
                      fetchSelection({ contact_id: form.contact_id })
                  "
                  @input="searchDeals"
                /><button
                  v-if="form.deal_id && !selectedProposal"
                  type="button"
                  class="rounded-xl border px-3"
                  @click="clearDeal"
                >
                  ✕
                </button>
              </div>
              <div
                v-if="!form.deal_id && filteredDeals.length"
                class="absolute z-20 mt-1 max-h-64 w-full overflow-auto rounded-xl border bg-n-solid-2 p-1 shadow-xl"
              >
                <button
                  v-for="d in filteredDeals"
                  :key="d.id"
                  type="button"
                  class="block w-full rounded-lg px-3 py-2 text-left hover:bg-n-slate-2"
                  @click="chooseDeal(d)"
                >
                  <b>{{ d.title }}</b
                  ><small class="block text-n-slate-11"
                    >{{
                      d.company_name ||
                      d.contact?.company_name ||
                      d.contact?.name ||
                      'Cliente'
                    }}
                    · {{ money(d.value_cents) }} ·
                    {{ d.stage?.name || d.status }}</small
                  >
                </button>
              </div>
            </label>
            <label
              >Proposta (opcional)
              <div class="mt-1 flex gap-2">
                <select
                  v-model="form.proposal_id"
                  :disabled="!form.deal_id"
                  class="w-full rounded-xl border p-2.5"
                  @change="
                    chooseProposal(
                      proposals.find(
                        p => String(p.id) === String(form.proposal_id)
                      )
                    )
                  "
                >
                  <option :value="null">Sem proposta</option>
                  <option v-for="p in proposals" :key="p.id" :value="p.id">
                    {{ p.proposal_number }} v{{ p.version_number }} —
                    {{ p.status_display }}
                  </option></select
                ><button
                  v-if="form.proposal_id"
                  type="button"
                  class="rounded-xl border px-3"
                  @click="clearProposal"
                >
                  ✕
                </button>
              </div>
              <small
                class="mt-1 block"
                :class="
                  proposals.length ? 'text-emerald-700' : 'text-amber-700'
                "
                >{{ proposalState.message }}</small
              >
              <button
                v-if="proposalState.attention_proposal"
                type="button"
                class="mt-1 text-xs font-semibold text-blue-700"
                @click="viewAttentionProposal"
              >
                Ver proposta
                {{ proposalState.attention_proposal.proposal_number }} →
              </button>
            </label>
            <label
              >Origem do pedido *<select
                v-model="form.order_origin"
                :disabled="!!selectedProposal"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option value="proposal_deal">Proposta / Negócio</option>
                <option value="direct_sale">Venda direta</option>
                <option value="renewal">Renovação</option>
                <option value="expansion">Upgrade / Expansão</option>
              </select></label
            >
            <label
              >Tipo de pedido *<select
                v-model="form.order_type"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option>Venda de produtos e serviços</option>
                <option>Venda de produtos</option>
                <option>Venda de serviços</option>
                <option>Renovação</option>
                <option>Upgrade / expansão</option>
              </select></label
            >
            <label
              >Data do pedido *<input
                v-model="form.order_date"
                type="date"
                class="mt-1 w-full rounded-xl border p-2.5"
            /></label>
            <label
              >Previsão de ativação<input
                v-model="form.activation_date"
                type="date"
                class="mt-1 w-full rounded-xl border p-2.5"
            /></label>
            <label
              >Responsável *<select
                v-model="form.owner_id"
                :disabled="!!selectedProposal"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option v-for="a in agents" :key="a.id" :value="a.id">
                  {{ a.name }}
                </option>
              </select></label
            >
            <label class="md:col-span-2 xl:col-span-3"
              >Observações<textarea
                v-model="form.notes"
                rows="3"
                class="mt-1 w-full rounded-xl border p-2.5"
                placeholder="Informações adicionais sobre o pedido..."
              />
            </label>
          </div>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <div class="mb-4 flex items-center justify-between">
            <h3 class="text-lg font-bold">Itens do pedido</h3>
            <div class="flex gap-2">
              <button
                class="rounded-xl border px-3 py-2 text-sm"
                @click="step = 2"
              >
                + Adicionar produto/serviço</button
              ><button
                class="rounded-xl border border-blue-200 px-3 py-2 text-sm text-blue-700"
                :disabled="!selectedProposal"
                @click="importProposal"
              >
                Importar da proposta
              </button>
            </div>
          </div>
          <div
            v-if="selectedProposal"
            class="mb-4 grid gap-2 rounded-xl bg-blue-50 p-3 text-xs md:grid-cols-3"
          >
            <span
              >Vigência:
              <b>{{ selectedProposal.term_months || '—' }} meses</b></span
            ><span
              >Pagamento:
              <b>{{
                selectedProposal.payment_condition ||
                selectedProposal.payment?.method ||
                '—'
              }}</b></span
            ><span
              >Recorrência:
              <b>{{ money(selectedProposal.monthly_cents) }}/mês</b></span
            >
          </div>
          <div v-if="form.items.length" class="overflow-x-auto">
            <table class="w-full min-w-[850px] text-sm">
              <thead class="bg-n-slate-2 text-xs uppercase text-n-slate-11">
                <tr>
                  <th class="p-2 text-left">Produto / Serviço</th>
                  <th>Qtd</th>
                  <th>Unidade</th>
                  <th>Valor unit.</th>
                  <th>Desconto</th>
                  <th>Valor único</th>
                  <th>MRR</th>
                  <th>Total</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="i in form.items"
                  :key="i.product_id"
                  class="border-t"
                >
                  <td class="p-3">
                    <b>{{ i.name }}</b>
                    <p class="text-xs text-n-slate-11">{{ i.description }}</p>
                  </td>
                  <td class="text-center">{{ i.quantity }}</td>
                  <td class="text-center">
                    {{ i.snapshot.unit_name || 'un.' }}
                  </td>
                  <td class="text-center">{{ money(i.unit_cents) }}</td>
                  <td class="text-center">{{ i.discount_percent }}%</td>
                  <td class="text-center">{{ money(i.one_time_cents) }}</td>
                  <td class="text-center">{{ money(i.recurring_cents) }}</td>
                  <td class="text-center font-semibold">
                    {{ money(i.one_time_cents) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p v-else class="py-8 text-center text-sm text-n-slate-11">
            Selecione uma proposta aceita ou adicione produtos e serviços na
            etapa Itens.
          </p>
        </article>
      </div>
      <aside class="space-y-4">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <div class="flex justify-between">
            <h3 class="font-bold">Cliente</h3>
            <RouterLink
              v-if="form.contact_id"
              :to="{
                name: 'crm_customer_360',
                params: { customerId: form.contact_id },
              }"
              class="text-xs text-blue-700"
            >
              Ver cliente →
            </RouterLink>
          </div>
          <p class="mt-4 text-lg font-bold">
            {{ selectedContact?.name || form.customer_name || 'A definir' }}
          </p>
          <p
            v-if="selectedContact?.company_name"
            class="mt-1 text-sm font-semibold text-n-slate-11"
          >
            {{ selectedContact.company_name }}
            <span v-if="selectedContact.customer_code"
              >· {{ selectedContact.customer_code }}</span
            >
          </p>
          <p class="mt-3 text-sm">
            ☎ {{ selectedContact?.phone_number || 'Não informado' }}
          </p>
          <p class="mt-2 text-sm">
            ✉ {{ selectedContact?.email || 'Não informado' }}
          </p>
          <p class="mt-2 text-sm">
            Responsável:
            {{ agents.find(a => a.id === form.owner_id)?.name || 'A definir' }}
          </p>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Rastreabilidade</h3>
          <p class="mt-3 text-sm">
            Origem
            <b class="float-right">{{
              {
                proposal_deal: 'Proposta/Negócio',
                direct_sale: 'Venda direta',
                renewal: 'Renovação',
                expansion: 'Upgrade/Expansão',
              }[form.order_origin]
            }}</b>
          </p>
          <p class="mt-3 text-sm">
            Negócio <b class="float-right">{{ selectedDeal?.title || '—' }}</b>
          </p>
          <p class="mt-3 text-sm">
            Proposta
            <b class="float-right">{{
              selectedProposal
                ? `${selectedProposal.proposal_number} v${selectedProposal.version_number}`
                : '—'
            }}</b>
          </p>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Ações após criar</h3>
          <label class="mt-3 flex justify-between text-sm"
            >Gerar contrato automaticamente
            <input v-model="form.generate_contract" type="checkbox" /></label
          ><label class="mt-3 flex justify-between text-sm"
            >Enviar para implantação
            <input
              v-model="form.send_to_implementation"
              type="checkbox" /></label
          ><label class="mt-3 flex justify-between text-sm"
            >Criar Projeto de Implantação
            <input
              v-model="form.create_implementation_project"
              type="checkbox"
              :disabled="!form.send_to_implementation" /></label
          ><label class="mt-3 flex justify-between text-sm"
            >Criar atividade de follow-up
            <input
              v-model="form.create_follow_up"
              type="checkbox"
              :disabled="!form.deal_id"
          /></label>
          <p class="mt-2 text-xs text-n-slate-11">
            {{ t('CRM.HOMOLOGATION.FOLLOW_UP_HELP') }}
          </p>
          <label
            v-if="form.create_follow_up && form.deal_id"
            class="mt-3 block text-sm"
            >{{ t('CRM.HOMOLOGATION.FOLLOW_UP_DATE')
            }}<input
              v-model="form.follow_up_due_at"
              type="datetime-local"
              required
              class="mt-1 w-full rounded-xl border p-2.5"
          /></label>
        </article>
      </aside>
    </section>

    <fieldset
      v-if="step === 2"
      :disabled="!!selectedProposal"
      class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_300px]"
    >
      <div class="space-y-4">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 class="text-lg font-bold">Produtos e serviços</h3>
              <p class="text-sm text-n-slate-11">
                Selecione os itens que farão parte do pedido.
              </p>
            </div>
            <input
              v-model="search"
              class="rounded-xl border px-3 py-2"
              placeholder="Buscar produto ou serviço..."
            />
          </div>
          <div class="grid gap-2 md:grid-cols-2">
            <button
              v-for="p in filteredProducts"
              :key="p.id"
              class="flex items-center justify-between rounded-xl border p-3 text-left hover:border-blue-300 hover:bg-blue-50/40"
              @click="addProduct(p)"
            >
              <span
                ><b>{{ p.name }}</b
                ><small class="block text-n-slate-11"
                  >{{ p.category }} · {{ p.billing_model }}</small
                ></span
              ><span class="font-semibold text-blue-700"
                >{{ money(p.unit_price_cents) }} ＋</span
              >
            </button>
          </div>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="mb-3 font-bold">Itens selecionados</h3>
          <div class="overflow-x-auto">
            <table class="w-full min-w-[950px] text-sm">
              <thead class="bg-n-slate-2 text-xs uppercase text-n-slate-11">
                <tr>
                  <th class="p-2 text-left">Produto / Serviço</th>
                  <th>Qtd</th>
                  <th>Unidade</th>
                  <th>Valor unit.</th>
                  <th>Desconto %</th>
                  <th>Valor único</th>
                  <th>MRR</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="(i, index) in form.items"
                  :key="`${i.product_id}-${index}`"
                  class="border-t"
                >
                  <td class="p-3">
                    <b>{{ i.name }}</b>
                    <p class="text-xs text-n-slate-11">{{ i.description }}</p>
                  </td>
                  <td>
                    <input
                      v-model.number="i.quantity"
                      type="number"
                      min="1"
                      class="w-20 rounded-lg border p-2"
                      @change="recalc(i)"
                    />
                  </td>
                  <td class="text-center">
                    {{ i.snapshot.unit_name || 'un.' }}
                  </td>
                  <td>
                    <input
                      v-model.number="i.unit_cents"
                      type="number"
                      min="0"
                      class="w-28 rounded-lg border p-2"
                      @change="recalc(i)"
                    />
                  </td>
                  <td>
                    <input
                      v-model.number="i.discount_percent"
                      type="number"
                      min="0"
                      max="100"
                      class="w-20 rounded-lg border p-2"
                      @change="recalc(i)"
                    />
                  </td>
                  <td class="text-center font-semibold">
                    {{ money(i.one_time_cents) }}
                  </td>
                  <td class="text-center font-semibold">
                    {{ money(i.recurring_cents) }}
                  </td>
                  <td>
                    <button class="text-red-600" @click="removeItem(index)">
                      ✕
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
      </div>
      <aside class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
        <h3 class="font-bold">Resumo dos itens</h3>
        <p class="mt-4 flex justify-between">
          Itens <b>{{ form.items.length }}</b>
        </p>
        <p class="mt-3 flex justify-between">
          Valor único <b>{{ money(subtotal) }}</b>
        </p>
        <p class="mt-3 flex justify-between">
          MRR <b>{{ money(monthly) }}</b>
        </p>
        <button
          v-if="selectedProposal"
          class="mt-5 w-full rounded-xl border border-blue-200 px-3 py-2 text-blue-700"
          @click="importProposal"
        >
          Importar novamente da proposta
        </button>
      </aside>
    </fieldset>

    <fieldset
      v-if="step === 3"
      :disabled="!!selectedProposal"
      class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_320px]"
    >
      <div class="space-y-4">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="text-lg font-bold">Condições financeiras</h3>
          <p class="mb-4 text-sm text-n-slate-11">
            Defina os valores, descontos, impostos e forma de pagamento do
            pedido.
          </p>
          <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            <label
              >Moeda<select class="mt-1 w-full rounded-xl border p-2.5">
                <option>Real (BRL) - R$</option>
              </select></label
            ><label
              >Meio de pagamento *<select
                v-model="form.payment_method"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option value="boleto">Boleto bancário</option>
                <option value="pix">PIX</option>
                <option value="transferencia">Transferência</option>
                <option value="cartao">Cartão</option>
              </select></label
            ><label
              >Condicao comercial<select
                v-model="form.payment_condition"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option value="cash">A vista</option>
                <option value="installments">Parcelas sem entrada</option>
                <option value="down_payment_installments">
                  Entrada + parcelas
                </option>
              </select></label
            >
            <label v-if="form.payment_condition === 'down_payment_installments'"
              >Entrada (R$)<input
                :value="form.down_payment_cents / 100"
                type="number"
                min="0"
                step="0.01"
                class="mt-1 w-full rounded-xl border p-2.5"
                @input="
                  form.down_payment_cents = Math.round(
                    Number($event.target.value) * 100
                  )
                "
            /></label>
            <label
              >Frete<select
                v-model="form.shipping_mode"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option value="not_applicable">Sem frete</option>
                <option value="included">Incluso</option>
                <option value="separate">Cobrado separadamente</option>
              </select></label
            >
            <label v-if="form.shipping_mode === 'separate'"
              >Frete (R$)<input
                :value="form.shipping_cents / 100"
                type="number"
                min="0"
                step="0.01"
                class="mt-1 w-full rounded-xl border p-2.5"
                @input="
                  form.shipping_cents = Math.round(
                    Number($event.target.value) * 100
                  )
                "
            /></label>
            <label
              v-if="form.shipping_mode === 'separate'"
              class="flex items-center gap-2"
              ><input v-model="form.shipping_in_installments" type="checkbox" />
              Incluir frete nas parcelas</label
            >
            <label class="flex items-center gap-2"
              ><input v-model="form.has_monthly_fee" type="checkbox" />
              Recorrencia mensal contratada</label
            >
            <label
              >Parcelas<select
                v-model="form.installments_count"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option v-for="n in 120" :key="n" :value="n">{{ n }}x</option>
              </select></label
            ><label
              >Data de vencimento<input
                v-model="form.first_due_date"
                type="date"
                class="mt-1 w-full rounded-xl border p-2.5" /></label
            ><label
              >Desconto geral (%)<input
                v-model.number="form.discount_percent"
                type="number"
                min="0"
                max="100"
                class="mt-1 w-full rounded-xl border p-2.5"
                @input="form.general_discount_cents = null" /></label
            ><label
              >Impostos (%)<input
                v-model.number="form.taxes_percent"
                type="number"
                min="0"
                class="mt-1 w-full rounded-xl border p-2.5" /></label
            ><label class="md:col-span-2"
              >Centro de custo<input
                v-model="form.cost_center"
                class="mt-1 w-full rounded-xl border p-2.5" /></label
            ><label class="md:col-span-2 xl:col-span-4"
              >Observações financeiras<textarea
                v-model="form.financial_notes"
                rows="3"
                class="mt-1 w-full rounded-xl border p-2.5"
              />
            </label>
          </div>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <div class="mb-4 flex justify-between">
            <div>
              <h3 class="font-bold">Parcelas</h3>
              <p class="text-sm text-n-slate-11">
                Geradas automaticamente a partir da condição de pagamento.
              </p>
            </div>
            <span
              class="rounded-xl bg-blue-50 px-3 py-2 text-sm text-blue-800"
              >{{ t('CRM.WORKFLOW_UI.AUTOMATIC_INSTALLMENTS') }}</span
            >
          </div>
          <table class="w-full text-sm">
            <thead class="bg-n-slate-2 text-xs uppercase text-n-slate-11">
              <tr>
                <th>#</th>
                <th>{{ t('CRM.WORKFLOW_UI.DUE_DATE') }}</th>
                <th>Descrição</th>
                <th>Valor</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="r in installmentRows"
                :key="r.number"
                class="border-t text-center"
              >
                <td class="p-3">{{ r.number }}</td>
                <td>
                  {{
                    new Date(`${r.date}T12:00:00`).toLocaleDateString('pt-BR')
                  }}
                </td>
                <td>Parcela {{ r.number }} de {{ installmentRows.length }}</td>
                <td>{{ money(r.value) }}</td>
                <td>
                  <span
                    class="rounded-full bg-amber-50 px-2 py-1 text-xs text-amber-700"
                    >{{ r.status }}</span
                  >
                </td>
              </tr>
            </tbody>
          </table>
        </article>
      </div>
      <aside class="space-y-4">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Resumo financeiro</h3>
          <p class="mt-2 flex justify-between">
            Frete <b>{{ money(financials.shipping_cents) }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Entrada <b>{{ money(financials.down_payment_cents) }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Frete a parte <b>{{ money(financials.upfront_shipping_cents) }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Saldo <b>{{ money(financials.balance_cents) }}</b>
          </p>
          <p class="mt-4 flex justify-between">
            Subtotal <b>{{ money(subtotal) }}</b>
          </p>
          <p class="mt-2 flex justify-between text-red-600">
            Desconto <b>- {{ money(discount) }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Impostos <b>{{ money(taxes) }}</b>
          </p>
          <p class="mt-4 flex justify-between border-t pt-3 text-lg">
            Valor total <b class="text-blue-700">{{ money(total) }}</b>
          </p>
          <div class="mt-4 grid grid-cols-2 gap-2">
            <div class="rounded-xl bg-blue-50 p-3">
              <small>Valor mensal (MRR)</small
              ><b class="block">{{ money(monthly) }}</b>
            </div>
            <div class="rounded-xl bg-blue-50 p-3">
              <small>Ticket médio</small
              ><b class="block">{{ money(ticket) }}</b>
            </div>
          </div>
        </article>
      </aside>
    </fieldset>

    <section
      v-if="step === 4"
      class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_320px]"
    >
      <div class="space-y-4">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="text-lg font-bold">Implantação dos serviços</h3>
          <p class="mb-4 text-sm text-n-slate-11">
            Configure como os serviços serão implantados e entregues ao cliente.
          </p>
          <div class="overflow-x-auto">
            <table class="w-full min-w-[900px] text-sm">
              <thead class="bg-n-slate-2 text-xs uppercase text-n-slate-11">
                <tr>
                  <th class="p-2 text-left">Produto / Serviço</th>
                  <th>Tipo de implantação</th>
                  <th>Responsável</th>
                  <th>Data prevista</th>
                  <th>Status</th>
                  <th>Observações</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="i in form.items"
                  :key="i.product_id"
                  class="border-t"
                >
                  <td class="p-3 font-semibold">{{ i.name }}</td>
                  <td>
                    <select
                      v-model="i.snapshot.implementation_type"
                      class="rounded-lg border p-2"
                    >
                      <option>Automática</option>
                      <option>Assistida</option>
                      <option>Manual</option>
                    </select>
                  </td>
                  <td>
                    <input
                      v-model="i.snapshot.implementation_owner"
                      class="w-36 rounded-lg border p-2"
                      placeholder="Responsável"
                    />
                  </td>
                  <td>
                    <input
                      v-model="i.snapshot.implementation_date"
                      type="date"
                      class="rounded-lg border p-2"
                    />
                  </td>
                  <td>
                    <span class="rounded-full bg-n-slate-3 px-2 py-1 text-xs">{{
                      i.snapshot.status
                    }}</span>
                  </td>
                  <td>
                    <input
                      v-model="i.snapshot.implementation_notes"
                      class="w-44 rounded-lg border p-2"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="mb-4 font-bold">Responsáveis e acompanhamento</h3>
          <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
            <label
              >Responsável interno *<input
                v-model="form.operation_owner_name"
                class="mt-1 w-full rounded-xl border p-2.5" /></label
            ><label
              >Responsável do cliente<input
                v-model="form.customer_owner_name"
                class="mt-1 w-full rounded-xl border p-2.5" /></label
            ><label
              >Equipe de implantação<input
                v-model="form.implementation_team"
                class="mt-1 w-full rounded-xl border p-2.5" /></label
            ><label
              >Prioridade<select
                v-model="form.priority"
                class="mt-1 w-full rounded-xl border p-2.5"
              >
                <option>Baixa</option>
                <option>Normal</option>
                <option>Alta</option>
                <option>Urgente</option>
              </select></label
            >
          </div>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Comunicação com o cliente</h3>
          <p
            class="mt-3 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900"
          >
            {{ t('CRM.HOMOLOGATION.COMMUNICATION_UNAVAILABLE') }}
          </p>
          <div class="mt-4 grid gap-3 md:grid-cols-2">
            <label class="flex items-center gap-2"
              ><input
                v-model="form.send_confirmation"
                type="checkbox"
                disabled
              />
              Enviar e-mail de confirmação do pedido</label
            ><label class="flex items-center gap-2"
              ><input v-model="form.send_schedule" type="checkbox" disabled />
              Enviar cronograma de implantação</label
            ><label class="flex items-center gap-2"
              ><input v-model="form.notify_steps" type="checkbox" disabled />
              Notificar o cliente sobre cada etapa</label
            ><label
              >Modelo de e-mail<select
                v-model="form.email_template"
                disabled
                class="ml-2 rounded-lg border p-2"
              >
                <option>Confirmação de pedido + cronograma</option>
                <option>Confirmação de pedido</option>
              </select></label
            >
          </div>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Observações da operação</h3>
          <textarea
            v-model="form.operation_notes"
            rows="4"
            class="mt-3 w-full rounded-xl border p-3"
            placeholder="Instruções adicionais para o time de implantação..."
          />
        </article>
      </div>
      <aside class="space-y-4">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Resumo do pedido</h3>
          <p class="mt-3 flex justify-between">
            Cliente <b>{{ form.customer_name }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Proposta <b>{{ selectedProposal?.proposal_number || '—' }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Valor total <b>{{ money(total) }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Itens <b>{{ form.items.length }}</b>
          </p>
          <p class="mt-2 flex justify-between">
            Prazo <b>{{ form.activation_date || 'A definir' }}</b>
          </p>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Checklist de implantação</h3>
          <label
            v-for="c in form.checklist"
            :key="c.label"
            class="mt-3 flex gap-2 text-sm"
            ><input v-model="c.done" type="checkbox" /> {{ c.label }}</label
          >
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Documentos de apoio</h3>
          <label
            class="mt-3 block cursor-pointer rounded-xl border border-dashed p-5 text-center text-sm text-n-slate-11"
            >Arraste ou clique para selecionar<input
              type="file"
              multiple
              class="hidden"
              @change="addFiles"
          /></label>
          <div
            v-for="(d, index) in form.documents"
            :key="`${d.name}-${index}`"
            class="mt-2 flex justify-between text-sm"
          >
            <span>{{ d.name }}</span
            ><button class="text-red-600" @click="removeDocument(index)">
              ✕
            </button>
          </div>
          <p class="mt-3 text-xs text-emerald-700">
            Os arquivos selecionados serão enviados e persistidos no pedido após
            a criação.
          </p>
        </article>
      </aside>
    </section>

    <section v-if="step === 5" class="space-y-4">
      <div class="rounded-2xl border border-blue-200 bg-blue-50 p-5">
        <div class="flex justify-between">
          <div>
            <h3 class="text-lg font-bold text-blue-800">
              ✓ Tudo pronto para finalizar!
            </h3>
            <p class="text-sm text-blue-700">
              Revise as informações abaixo. Você pode voltar e editar qualquer
              etapa antes de confirmar o pedido.
            </p>
          </div>
          <button
            class="rounded-xl border border-blue-200 bg-n-solid-2 px-3 py-2 text-blue-700"
            @click="step = 1"
          >
            Editar pedido
          </button>
        </div>
      </div>
      <div class="grid gap-4 xl:grid-cols-[1fr_1fr_360px]">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Dados do cliente</h3>
          <p class="mt-4 text-xl font-bold">{{ form.customer_name }}</p>
          <p class="mt-3 text-sm">
            Contato:
            {{
              selectedContact?.email ||
              selectedContact?.phone_number ||
              'Não informado'
            }}
          </p>
          <p class="mt-2 text-sm">
            Negócio: {{ selectedDeal?.title || 'Pedido direto' }}
          </p>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Informações do pedido</h3>
          <p class="mt-4">
            Origem
            <b class="float-right">{{
              selectedProposal ? 'Proposta' : 'CRM'
            }}</b>
          </p>
          <p class="mt-2">
            Proposta
            <b class="float-right">{{
              selectedProposal?.proposal_number || '—'
            }}</b>
          </p>
          <p class="mt-2">
            Responsável
            <b class="float-right">{{
              agents.find(a => a.id === form.owner_id)?.name
            }}</b>
          </p>
          <p class="mt-2">
            Data
            <b class="float-right">{{
              new Date(`${form.order_date}T12:00:00`).toLocaleDateString(
                'pt-BR'
              )
            }}</b>
          </p>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Condições financeiras</h3>
          <p class="mt-4 flex justify-between">
            Subtotal <b>{{ money(subtotal) }}</b>
          </p>
          <p class="mt-2 flex justify-between text-red-600">
            Desconto <b>- {{ money(discount) }}</b>
          </p>
          <p class="mt-3 flex justify-between border-t pt-3 text-lg">
            Total do pedido <b class="text-blue-700">{{ money(total) }}</b>
          </p>
          <div class="mt-4 grid grid-cols-2 gap-2">
            <div class="rounded-xl bg-blue-50 p-3">
              <small>MRR</small><b class="block">{{ money(monthly) }}</b>
            </div>
            <div class="rounded-xl bg-blue-50 p-3">
              <small>Ticket médio</small
              ><b class="block">{{ money(ticket) }}</b>
            </div>
          </div>
        </article>
      </div>
      <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
        <h3 class="mb-3 font-bold">Itens do pedido</h3>
        <table class="w-full text-sm">
          <thead class="bg-n-slate-2 text-xs uppercase text-n-slate-11">
            <tr>
              <th class="p-2 text-left">Produto / Serviço</th>
              <th>Qtd</th>
              <th>Valor unit.</th>
              <th>Desconto</th>
              <th>Total</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="i in form.items" :key="i.product_id" class="border-t">
              <td class="p-3">
                <b>{{ i.name }}</b>
                <p class="text-xs text-n-slate-11">{{ i.description }}</p>
              </td>
              <td class="text-center">{{ i.quantity }}</td>
              <td class="text-center">{{ money(i.unit_cents) }}</td>
              <td class="text-center">{{ i.discount_percent }}%</td>
              <td class="text-center font-semibold">
                {{ money(i.one_time_cents) }}
              </td>
            </tr>
          </tbody>
        </table>
      </article>
      <div class="grid gap-4 lg:grid-cols-2">
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Implantação e entrega</h3>
          <p class="mt-3">
            Equipe: <b>{{ form.implementation_team }}</b>
          </p>
          <p class="mt-2">
            Responsável: <b>{{ form.operation_owner_name || 'A definir' }}</b>
          </p>
          <p class="mt-2">
            Previsão: <b>{{ form.activation_date || 'A definir' }}</b>
          </p>
        </article>
        <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
          <h3 class="font-bold">Comunicação com o cliente</h3>
          <p class="mt-3">
            {{ form.send_confirmation ? '✓' : '○' }} Enviar confirmação do
            pedido
          </p>
          <p class="mt-2">
            {{ form.send_schedule ? '✓' : '○' }} Enviar cronograma
          </p>
          <p class="mt-2">
            {{ form.notify_steps ? '✓' : '○' }} Notificar cada etapa
          </p>
        </article>
      </div>
    </section>

    <footer class="mt-5 flex flex-wrap justify-between gap-3">
      <button
        class="rounded-xl border bg-n-solid-2 px-5 py-3"
        :disabled="step === 1"
        @click="step--"
      >
        ← Anterior
      </button>
      <div class="flex gap-2">
        <button
          class="rounded-xl border bg-n-solid-2 px-5 py-3 font-semibold"
          :disabled="saving"
          @click="save('draft')"
        >
          Salvar como rascunho</button
        ><button
          v-if="step < 5"
          class="rounded-xl bg-blue-600 px-6 py-3 font-semibold text-white"
          @click="next"
        >
          Avançar para {{ steps[step][0].toLowerCase() }} →</button
        ><button
          v-else
          class="rounded-xl bg-blue-600 px-6 py-3 font-semibold text-white"
          :disabled="saving"
          @click="save('pending')"
        >
          {{ saving ? 'Salvando…' : '✓ Finalizar pedido' }}
        </button>
      </div>
    </footer>
  </div>
</template>
