<script setup>
import OperationsLinks from '../../../jrcOperations/components/OperationsLinks.vue';
import { crmControlClasses } from '../../crmControlClasses';
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useProjects } from '../../../jrcProjects/useProjects';
import { errorMessage } from '../../../jrcOperations/api';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import ContactsAPI from 'dashboard/api/contacts';
import AgentsAPI from 'dashboard/api/agents';
import { dealsAPI, pipelinesAPI, stagesAPI, productsAPI, activitiesAPI } from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import CrmValueDisplay from '../../components/shared/CrmValueDisplay.vue';
import { formatCrmDateTime } from '../../utils/dateTime';

const { projectText } = useProjects();
const store = useStore();
const route = useRoute();
const router = useRouter();
const showForm = ref(false);
const showContactForm = ref(false);
const saving = ref(false);
const savingContact = ref(false);
const pipelines = ref([]);
const stages = ref([]);
const contacts = ref([]);
const products = ref([]);
const agents = ref([]);
const dealItems = ref([]);
const editingDetails = ref(false);
const detailsSaving = ref(false);
const detailsStages = ref([]);
const form = reactive({
  title: '', contact_id: '', conversation_id: '', pipeline_id: '', stage_id: '', value: '', source: '',
  expected_close_at: '', probability: 30, description: '', next_activity_type: 'call', next_activity_at: '', next_activity_title: '',
});
const contactForm = reactive({ name: '', email: '', phone_number: '' });
const productForm = reactive({ product_id: '', quantity: 1, unit_price: '', discount: '' });
const detailsForm = reactive({ contact_id: '', stage_id: '', owner_id: '', source: '', value: '' });
const detailsProductForm = reactive({ product_id: '', quantity: 1, unit_price: '', discount: '' });

const sourceOptions = [
  ['whatsapp', 'WhatsApp'], ['ligacoes', 'Ligações'], ['ligacoes_whatsapp', 'Ligações WhatsApp'],
  ['email', 'E-mail'], ['instagram', 'Instagram'], ['facebook', 'Facebook'], ['webchat', 'Webchat'],
  ['indicacao', 'Indicação'], ['campanha', 'Campanha'], ['prospeccao_ativa', 'Prospecção ativa'], ['outro', 'Outro'],
];

const deals = computed(() => store.getters['jrcCrm/deals/allDeals'] || []);
const loading = computed(() => store.getters['jrcCrm/deals/isLoading']);
const error = computed(() => store.getters['jrcCrm/deals/error']);
const detailLoading = ref(false);
const detailError = ref('');
const loadedDetailKey = ref('');
const detailKey = () => `${route.params.accountId}:${route.query.dealId || ''}`;
const selectedDeal = computed(() => {
  if (!route.query.dealId || detailLoading.value || detailError.value || loadedDetailKey.value !== detailKey()) return null;
  const current = store.getters['jrcCrm/deals/currentDeal'];
  return String(current?.id) === String(route.query.dealId) ? current : null;
});
const itemsSubtotal = computed(() => dealItems.value.reduce((sum, item) => sum + Number(item.unit_price_cents || 0) * Number(item.quantity || 0), 0));
const itemsDiscount = computed(() => dealItems.value.reduce((sum, item) => sum + Number(item.discount_cents || 0), 0));
const itemsTotal = computed(() => Math.max(itemsSubtotal.value - itemsDiscount.value, 0));

const centsFromInput = value => Math.round(Number(value || 0) * 100);
const moneyInput = cents => (Number(cents || 0) / 100).toFixed(2);
const closeDetails = () => { editingDetails.value = false; const query = { ...route.query }; delete query.dealId; router.replace({ query }); };
const openConversation = conversation => router.push({ name: 'inbox_conversation', params: { accountId: route.params.accountId, conversation_id: conversation.display_id || conversation.id } });

const loadContacts = async () => {
  const { data } = await ContactsAPI.get(1);
  contacts.value = data.payload || [];
};
const loadStages = async () => {
  if (!form.pipeline_id) return;
  const { data } = await stagesAPI.list({ pipeline_id: form.pipeline_id });
  stages.value = data;
  if (!stages.value.some(stage => String(stage.id) === String(form.stage_id))) form.stage_id = data[0]?.id || '';
};
const loadProducts = async () => {
  const { data } = await productsAPI.list({ active: true });
  products.value = data;
};
const resetForm = () => {
  form.title = ''; form.contact_id = ''; form.conversation_id = ''; form.value = ''; form.source = ''; form.description = '';
  form.expected_close_at = ''; form.probability = 30; form.next_activity_type = 'call'; form.next_activity_at = ''; form.next_activity_title = '';
  form.pipeline_id = pipelines.value[0]?.id || ''; form.stage_id = '';
  dealItems.value = [];
};
const openForm = () => {
  resetForm();
  form.contact_id = route.query.contactId || '';
  form.conversation_id = route.query.conversationId || '';
  showForm.value = true;
};

const createContact = async () => {
  if (!contactForm.name.trim()) return;
  savingContact.value = true;
  try {
    const { data } = await ContactsAPI.create({
      name: contactForm.name.trim(), email: contactForm.email || undefined, phone_number: contactForm.phone_number || undefined,
    });
    const created = data?.payload?.contact;
    await loadContacts();
    if (created?.id) form.contact_id = created.id;
    contactForm.name = ''; contactForm.email = ''; contactForm.phone_number = '';
    showContactForm.value = false;
    useAlert('Cliente cadastrado com sucesso.');
  } catch (requestError) {
    useAlert(requestError.response?.data?.message || 'Não foi possível cadastrar o cliente.');
  } finally { savingContact.value = false; }
};

const selectProduct = () => {
  const product = products.value.find(item => String(item.id) === String(productForm.product_id));
  productForm.unit_price = product ? moneyInput(product.unit_price_cents) : '';
};
const addProductDraft = () => {
  const product = products.value.find(item => String(item.id) === String(productForm.product_id));
  if (!product) return;
  dealItems.value.push({
    product_id: product.id, product, quantity: Number(productForm.quantity || 1),
    unit_price_cents: centsFromInput(productForm.unit_price), discount_cents: centsFromInput(productForm.discount),
  });
  productForm.product_id = ''; productForm.quantity = 1; productForm.unit_price = ''; productForm.discount = '';
};
const removeProductDraft = index => dealItems.value.splice(index, 1);


const hydrateDetailsForm = async deal => {
  if (!deal) return;
  detailsForm.contact_id = deal.contact_id || '';
  detailsForm.stage_id = deal.stage_id || '';
  detailsForm.owner_id = deal.owner_id || '';
  detailsForm.source = deal.source || '';
  detailsForm.value = moneyInput(deal.value_cents);
  try {
    const { data } = await stagesAPI.list({ pipeline_id: deal.pipeline_id });
    detailsStages.value = data;
  } catch {
    detailsStages.value = [];
  }
};

const toggleDetailsEdit = async () => {
  if (!selectedDeal.value) return;
  if (!editingDetails.value) await hydrateDetailsForm(selectedDeal.value);
  editingDetails.value = !editingDetails.value;
};

const saveDetails = async () => {
  if (!selectedDeal.value) return;
  detailsSaving.value = true;
  try {
    await dealsAPI.update(selectedDeal.value.id, { deal: {
      contact_id: detailsForm.contact_id || null,
      stage_id: detailsForm.stage_id,
      owner_id: detailsForm.owner_id || undefined,
      source: detailsForm.source,
      value_cents: centsFromInput(detailsForm.value),
    }});
    await store.dispatch('jrcCrm/deals/fetchDeals');
    await loadDetails();
    editingDetails.value = false;
    useAlert('Negócio atualizado com sucesso.');
  } catch (requestError) {
    useAlert(requestError.response?.data?.errors?.join(', ') || 'Não foi possível atualizar o negócio.');
  } finally { detailsSaving.value = false; }
};

const selectDetailsProduct = () => {
  const product = products.value.find(item => String(item.id) === String(detailsProductForm.product_id));
  detailsProductForm.unit_price = product ? moneyInput(product.unit_price_cents) : '';
};

const addDetailsProduct = async () => {
  if (!selectedDeal.value || !detailsProductForm.product_id) return;
  try {
    await dealsAPI.createProduct(selectedDeal.value.id, { item: {
      product_id: detailsProductForm.product_id,
      quantity: Number(detailsProductForm.quantity || 1),
      unit_price_cents: centsFromInput(detailsProductForm.unit_price),
      discount_cents: centsFromInput(detailsProductForm.discount),
    }});
    detailsProductForm.product_id = ''; detailsProductForm.quantity = 1; detailsProductForm.unit_price = ''; detailsProductForm.discount = '';
    await store.dispatch('jrcCrm/deals/fetchDeals');
    await loadDetails();
  } catch (requestError) {
    useAlert(requestError.response?.data?.errors?.join(', ') || 'Não foi possível adicionar o produto.');
  }
};

const updateDetailsProduct = async item => {
  if (!selectedDeal.value) return;
  try {
    await dealsAPI.updateProduct(selectedDeal.value.id, item.id, { item: {
      quantity: Number(item.quantity || 1),
      unit_price_cents: Number(item.unit_price_cents || 0),
      discount_cents: Number(item.discount_cents || 0),
    }});
    await store.dispatch('jrcCrm/deals/fetchDeals');
    await loadDetails();
  } catch { useAlert('Não foi possível atualizar o produto.'); }
};

const removeDetailsProduct = async item => {
  if (!selectedDeal.value) return;
  try {
    await dealsAPI.deleteProduct(selectedDeal.value.id, item.id);
    await store.dispatch('jrcCrm/deals/fetchDeals');
    await loadDetails();
  } catch { useAlert('Não foi possível remover o produto.'); }
};

const save = async () => {
  saving.value = true;
  try {
    const { data: createdDeal } = await dealsAPI.create({ deal: {
      title: form.title, contact_id: form.contact_id || null, conversation_id: form.conversation_id || null,
      pipeline_id: form.pipeline_id, stage_id: form.stage_id,
      value_cents: dealItems.value.length ? itemsTotal.value : centsFromInput(form.value), source: form.source,
      expected_close_at: form.expected_close_at || null, probability: Number(form.probability || 0), description: form.description,
    }});
    for (const item of dealItems.value) {
      // eslint-disable-next-line no-await-in-loop
      await dealsAPI.createProduct(createdDeal.id, { item: {
        product_id: item.product_id, quantity: item.quantity, unit_price_cents: item.unit_price_cents, discount_cents: item.discount_cents,
      }});
    }
    if (form.next_activity_at && form.next_activity_title.trim()) {
      await activitiesAPI.create({ activity: { deal_id: createdDeal.id, activity_type: form.next_activity_type, title: form.next_activity_title.trim(), due_at: form.next_activity_at } });
    }
    showForm.value = false;
    await Promise.all([store.dispatch('jrcCrm/deals/fetchDeals'), store.dispatch('jrcCrm/activities/fetchActivities')]);
    useAlert('Negócio criado com sucesso.');
  } catch (requestError) {
    useAlert(requestError.response?.data?.errors?.join(', ') || 'Não foi possível criar o negócio.');
  } finally { saving.value = false; }
};
let detailGeneration = 0;
async function loadDetails() {
  const current = ++detailGeneration;
  const key = detailKey();
  const dealId = route.query.dealId;
  detailLoading.value = Boolean(dealId); detailError.value = ''; loadedDetailKey.value = '';
  editingDetails.value = false;
  store.commit('jrcCrm/deals/SET_CURRENT_DEAL', null);
  if (!dealId) return;
  try {
    const response = await dealsAPI.show(dealId);
    if (current !== detailGeneration || key !== detailKey()) return;
    store.commit('jrcCrm/deals/SET_CURRENT_DEAL', response.data?.payload || response.data);
    loadedDetailKey.value = key;
  } catch (requestError) {
    if (current === detailGeneration && key === detailKey()) detailError.value = errorMessage(requestError);
  } finally {
    if (current === detailGeneration) detailLoading.value = false;
  }
}
watch(() => [route.params.accountId, route.query.dealId], loadDetails, { immediate: true });
onBeforeUnmount(() => { detailGeneration += 1; });

watch(() => form.pipeline_id, loadStages);
onMounted(async () => {
  const [pipelinesResponse] = await Promise.all([
    pipelinesAPI.list(), loadContacts(), loadProducts(), AgentsAPI.get().then(({ data }) => { agents.value = data || []; }), store.dispatch('jrcCrm/deals/fetchDeals'),
  ]);
  pipelines.value = pipelinesResponse.data;
  form.pipeline_id = pipelines.value[0]?.id || '';
  await loadStages();
  if (route.query.new === '1' || route.query.conversationId || route.query.contactId) openForm();
});
</script>

<template>
  <div class="flex h-full flex-col bg-n-surface-1 p-6">
    <div class="mb-6 flex items-center justify-between gap-3">
      <div class="flex items-center gap-3"><span class="flex size-11 items-center justify-center rounded-2xl bg-n-blue-3 text-n-blue-11"><i class="i-lucide-handshake size-5" /></span><div><h2 class="text-2xl font-bold text-n-slate-12">Negócios</h2><p class="text-sm text-n-slate-9">Oportunidades comerciais em andamento</p></div></div>
      <div class="flex gap-2"><RouterLink :to="{ name: 'crm_funnel' }" class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold text-n-slate-12 shadow-sm">Ver Funil</RouterLink><button type="button" class="rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white shadow-md" @click="openForm">Novo Negócio</button></div>
    </div>
    <div class="flex-1 overflow-auto rounded-2xl border border-n-weak bg-n-solid-2 shadow-sm">
      <table class="min-w-full table-fixed divide-y divide-n-weak text-sm"><thead class="bg-n-alpha-2 text-left text-xs uppercase text-n-slate-10"><tr><th class="w-[38%] px-4 py-3">Negócio / Cliente</th><th class="w-[17%] px-3 py-3">Etapa</th><th class="w-[14%] px-3 py-3">Valor</th><th class="w-[16%] px-3 py-3">Responsável</th><th class="w-[10%] px-3 py-3">Status</th><th class="w-[5%] px-3 py-3 text-right">Ações</th></tr></thead><tbody class="divide-y divide-n-weak">
        <tr v-if="loading"><td colspan="6" class="px-5 py-12 text-center text-n-slate-10">Carregando negócios…</td></tr><tr v-else-if="error"><td colspan="6" class="px-5 py-12 text-center text-n-ruby-11">{{ error }}</td></tr><tr v-else-if="!deals.length"><td colspan="6" class="px-5 py-12 text-center text-n-slate-10">Nenhum negócio encontrado.</td></tr>
        <tr v-for="deal in deals" :key="deal.id" class="cursor-pointer hover:bg-n-alpha-2" @click="router.push({ query: { ...route.query, dealId: deal.id } })"><td class="px-4 py-3"><p class="truncate font-semibold text-n-slate-12" :title="deal.title">{{ deal.title }}</p><p class="truncate text-xs text-n-slate-10" :title="deal.contact?.name">{{ deal.contact?.name || 'Sem contato vinculado' }}</p></td><td class="px-3 py-3 text-n-slate-11">{{ deal.stage?.name || deal.stage_name || '-' }}</td><td class="px-3 py-3 font-semibold"><CrmValueDisplay :cents="deal.value_cents" /></td><td class="truncate px-3 py-3 text-n-slate-11">{{ deal.owner?.name || deal.owner_name || '-' }}</td><td class="px-3 py-3"><CrmStatusBadge :value="deal.status" /></td><td class="px-3 py-3 text-right"><button type="button" class="inline-flex size-8 items-center justify-center rounded-lg border border-n-weak text-n-slate-11 hover:bg-n-alpha-3" title="Abrir negócio" @click.stop="router.push({ query: { ...route.query, dealId: deal.id } })"><i class="i-lucide-chevron-right size-4" /></button></td></tr>
      </tbody></table>
    </div>

    <Teleport to="body">
      <div v-if="route.query.dealId && (detailLoading || detailError)" class="fixed inset-0 z-[80] flex justify-end bg-black/40" @click.self="closeDetails">
        <aside class="h-full w-full max-w-2xl overflow-auto bg-n-solid-2 p-6 shadow-2xl">
          <button class="mb-4 rounded-lg border border-n-weak px-3 py-2" @click="closeDetails">{{ projectText('CLOSE_RELATED', 'Fechar') }}</button>
          <p v-if="detailLoading" role="status">{{ projectText('RELATED_DEAL_LOADING', 'Carregando negócio...') }}</p>
          <div v-else role="alert"><p>{{ detailError }}</p><button class="mt-4 rounded-lg border border-n-weak px-3 py-2" @click="loadDetails">{{ projectText('RETRY', 'Tentar novamente') }}</button></div>
        </aside>
      </div>
      <div v-if="showForm" :class="crmControlClasses" class="fixed inset-0 z-[80] flex items-center justify-center bg-black/45 p-4">
        <form class="max-h-[94vh] w-full max-w-4xl overflow-auto rounded-2xl bg-n-solid-2 p-6 shadow-2xl" @submit.prevent="save">
          <div class="flex items-start justify-between gap-4"><div><div class="flex items-center gap-3"><span class="grid size-11 place-content-center rounded-xl bg-blue-700 text-white"><i class="i-lucide-briefcase-business size-5" /></span><div><h3 class="text-xl font-bold text-n-slate-12">Novo negócio</h3><p class="text-xs text-n-slate-9">Registre uma nova oportunidade comercial</p></div></div><p v-if="form.conversation_id" class="mt-2 text-xs text-n-teal-11">Criando a partir da conversa #{{ form.conversation_id }}.</p></div><button type="button" class="i-lucide-x size-5" @click="showForm = false" /></div>
          <div class="my-5 grid grid-cols-3 gap-3 text-xs font-semibold"><div class="rounded-xl bg-blue-50 p-3 text-blue-700"><span class="mr-2 inline-grid size-6 place-content-center rounded-full bg-blue-600 text-white">1</span>Informações</div><div class="rounded-xl bg-violet-50 p-3 text-violet-700"><span class="mr-2 inline-grid size-6 place-content-center rounded-full bg-violet-600 text-white">2</span>Produtos e valores</div><div class="rounded-xl bg-emerald-50 p-3 text-emerald-700"><span class="mr-2 inline-grid size-6 place-content-center rounded-full bg-emerald-600 text-white">3</span>Próxima ação</div></div>
          <section class="rounded-2xl border border-n-weak p-4"><h4 class="mb-3 flex items-center gap-2 font-semibold text-n-slate-12"><i class="i-lucide-info size-4 text-blue-600" />Informações da oportunidade</h4><div class="grid gap-3 md:grid-cols-2"><label class="text-xs font-semibold">Título do negócio *<input v-model="form.title" required class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" placeholder="Ex.: STIR/SHAKEN" /></label><label class="text-xs font-semibold">Cliente<select v-model="form.contact_id" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option value="">Selecione</option><option v-for="contact in contacts" :key="contact.id" :value="contact.id">{{ contact.name || contact.email || contact.phone_number }}</option></select></label><label class="text-xs font-semibold">Funil *<select v-model="form.pipeline_id" required class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" @change="loadStages"><option v-for="pipeline in pipelines" :key="pipeline.id" :value="pipeline.id">{{ pipeline.name }}</option></select></label><label class="text-xs font-semibold">Etapa *<select v-model="form.stage_id" required class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option v-for="stage in stages" :key="stage.id" :value="stage.id">{{ stage.name }}</option></select></label><label class="text-xs font-semibold">Origem<select v-model="form.source" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option value="">Sem origem</option><option v-for="source in sourceOptions" :key="source[0]" :value="source[0]">{{ source[1] }}</option></select></label><label class="text-xs font-semibold">Probabilidade<select v-model.number="form.probability" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option v-for="p in [10,20,30,40,50,60,70,80,90,100]" :key="p" :value="p">{{ p }}%</option></select></label><label class="text-xs font-semibold">Previsão de fechamento<input v-model="form.expected_close_at" type="date" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" /></label><label class="text-xs font-semibold md:col-span-2">Observações<textarea v-model="form.description" rows="2" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" placeholder="Histórico, requisitos e próximos passos…" /></label></div></section>
          <section class="mt-4 rounded-2xl border border-n-weak p-4"><h4 class="mb-3 flex items-center gap-2 font-semibold text-n-slate-12"><i class="i-lucide-package-plus size-4 text-violet-600" />Produtos e valores</h4><div class="grid gap-2 md:grid-cols-[1.5fr_80px_130px_120px_auto]"><select v-model="productForm.product_id" class="rounded-lg border border-n-weak px-3 py-2 text-sm" @change="selectProduct"><option value="">Selecionar produto</option><option v-for="product in products" :key="product.id" :value="product.id">{{ product.name }}</option></select><input v-model.number="productForm.quantity" type="number" min="1" class="rounded-lg border border-n-weak px-2 py-2" placeholder="Qtd" /><input v-model="productForm.unit_price" type="number" min="0" step="0.01" class="rounded-lg border border-n-weak px-2 py-2" placeholder="Preço" /><input v-model="productForm.discount" type="number" min="0" step="0.01" class="rounded-lg border border-n-weak px-2 py-2" placeholder="Desconto" /><button type="button" class="rounded-lg bg-blue-700 px-3 py-2 text-sm font-semibold text-white" @click="addProductDraft">+ Adicionar</button></div><div v-if="dealItems.length" class="mt-4 overflow-auto"><table class="min-w-full text-sm"><thead><tr class="border-b border-n-weak text-left text-xs uppercase text-n-slate-10"><th class="py-2">Produto</th><th class="py-2 text-right">Qtd</th><th class="py-2 text-right">Unitário</th><th class="py-2 text-right">Desconto</th><th class="py-2 text-right">Total</th><th></th></tr></thead><tbody><tr v-for="(item,index) in dealItems" :key="`${item.product_id}-${index}`" class="border-b border-n-weak"><td class="py-2">{{ item.product.name }}</td><td class="py-2 text-right">{{ item.quantity }}</td><td class="py-2 text-right">R$ {{ moneyInput(item.unit_price_cents) }}</td><td class="py-2 text-right">R$ {{ moneyInput(item.discount_cents) }}</td><td class="py-2 text-right font-semibold">R$ {{ moneyInput(item.unit_price_cents * item.quantity - item.discount_cents) }}</td><td class="text-right"><button type="button" class="i-lucide-trash-2 text-red-500" @click="removeProductDraft(index)" /></td></tr></tbody></table><div class="ml-auto mt-3 grid max-w-xs gap-1 text-sm"><div class="flex justify-between"><span>Subtotal</span><strong>R$ {{ moneyInput(itemsSubtotal) }}</strong></div><div class="flex justify-between"><span>Desconto</span><strong>R$ {{ moneyInput(itemsDiscount) }}</strong></div><div class="flex justify-between border-t border-n-weak pt-2 text-lg"><span>Valor total</span><strong class="text-emerald-600">R$ {{ moneyInput(itemsTotal) }}</strong></div></div></div><input v-else v-model="form.value" type="number" min="0" step="0.01" placeholder="Valor do negócio (R$)" class="mt-3 w-full rounded-lg border border-n-weak px-3 py-2" /></section>
          <section class="mt-4 rounded-2xl border border-n-weak p-4"><h4 class="mb-3 flex items-center gap-2 font-semibold text-n-slate-12"><i class="i-lucide-calendar-plus size-4 text-emerald-600" />Próxima ação</h4><div class="grid gap-3 md:grid-cols-3"><label class="text-xs font-semibold">Tipo<select v-model="form.next_activity_type" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option value="call">Ligação</option><option value="meeting">Reunião</option><option value="whatsapp">WhatsApp</option><option value="email">E-mail</option><option value="follow_up">Acompanhamento</option></select></label><label class="text-xs font-semibold">Data e hora<input v-model="form.next_activity_at" type="datetime-local" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" /></label><label class="text-xs font-semibold">Título<input v-model="form.next_activity_title" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" placeholder="Ex.: Ligação de retorno" /></label></div></section>
          <div class="mt-5 flex justify-end gap-2"><button type="button" class="rounded-xl border border-n-weak px-4 py-2.5 text-sm font-semibold" @click="showForm = false">Cancelar</button><button type="submit" :disabled="saving" class="rounded-xl bg-blue-700 px-5 py-2.5 text-sm font-semibold text-white shadow-md disabled:opacity-50"><i class="i-lucide-check mr-1 size-4" /> Criar negócio</button></div>
        </form>
      </div>

      <div v-if="selectedDeal" class="fixed inset-0 z-[80] flex justify-end bg-black/40" @click.self="closeDetails"><aside class="h-full w-full max-w-2xl overflow-auto bg-n-solid-2 p-6 shadow-2xl"><div class="flex items-start justify-between gap-3"><div><p class="text-xs font-semibold uppercase text-n-slate-10">Negócio</p><h3 class="mt-1 text-xl font-bold text-n-slate-12">{{ selectedDeal.title }}</h3></div><div class="flex gap-2"><button type="button" class="rounded-lg border border-n-weak px-3 py-2 text-sm font-semibold" @click="toggleDetailsEdit"><i class="i-lucide-pencil mr-1" /> {{ editingDetails ? 'Cancelar edição' : 'Editar' }}</button><button type="button" class="i-lucide-x size-5" @click="closeDetails" /></div></div>
        <form v-if="editingDetails" class="mt-6 space-y-4 rounded-xl border border-n-weak p-4" @submit.prevent="saveDetails"><div class="grid gap-3 md:grid-cols-2"><label class="text-sm font-medium">Cliente<select v-model="detailsForm.contact_id" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option value="">Sem cliente</option><option v-for="contact in contacts" :key="contact.id" :value="contact.id">{{ contact.name || contact.email || contact.phone_number }}</option></select></label><label class="text-sm font-medium">Responsável<select v-model="detailsForm.owner_id" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name || agent.email }}</option></select></label><label class="text-sm font-medium">Etapa<select v-model="detailsForm.stage_id" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option v-for="stage in detailsStages" :key="stage.id" :value="stage.id">{{ stage.name }}</option></select></label><label class="text-sm font-medium">Origem<select v-model="detailsForm.source" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"><option value="">Sem origem</option><option v-for="source in sourceOptions" :key="source[0]" :value="source[0]">{{ source[1] }}</option></select></label><label class="text-sm font-medium md:col-span-2">Valor do negócio (R$)<input v-model="detailsForm.value" type="number" min="0" step="0.01" class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" /></label></div><div class="flex justify-end"><button :disabled="detailsSaving" class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"><i class="i-lucide-save mr-1" /> Salvar alterações</button></div></form>
        <dl v-else class="mt-6 grid grid-cols-2 gap-4 rounded-xl border border-n-weak p-4 text-sm"><div><dt class="text-n-slate-10">Valor</dt><dd class="mt-1 font-semibold"><CrmValueDisplay :cents="selectedDeal.value_cents" /></dd></div><div><dt class="text-n-slate-10">Status</dt><dd class="mt-1"><CrmStatusBadge :value="selectedDeal.status" /></dd></div><div><dt class="text-n-slate-10">Etapa <i class="i-lucide-pencil ml-1 size-3" /></dt><dd class="mt-1 font-medium">{{ selectedDeal.stage?.name || '-' }}</dd></div><div><dt class="text-n-slate-10">Responsável <i class="i-lucide-pencil ml-1 size-3" /></dt><dd class="mt-1 font-medium">{{ selectedDeal.owner?.name || '-' }}</dd></div><div class="col-span-2"><dt class="text-n-slate-10">Cliente <i class="i-lucide-pencil ml-1 size-3" /></dt><dd class="mt-1 font-medium">{{ selectedDeal.contact?.name || 'Sem contato vinculado' }}</dd><p v-if="selectedDeal.contact?.phone_number" class="text-xs text-n-slate-10">{{ selectedDeal.contact.phone_number }}</p><p v-if="selectedDeal.contact?.email" class="text-xs text-n-slate-10">{{ selectedDeal.contact.email }}</p></div><div><dt class="text-n-slate-10">Origem <i class="i-lucide-pencil ml-1 size-3" /></dt><dd class="mt-1 font-medium">{{ sourceOptions.find(source => source[0] === selectedDeal.source)?.[1] || selectedDeal.source || '-' }}</dd></div><div><dt class="text-n-slate-10">Próxima atividade</dt><dd class="mt-1 font-medium">{{ selectedDeal.next_activity?.title || 'Sem próxima atividade' }}<span v-if="selectedDeal.next_activity?.due_at" class="block text-xs text-n-slate-10">{{ selectedDeal.next_activity.due_at_display || formatCrmDateTime(selectedDeal.next_activity.due_at) }}</span></dd></div></dl>
        <section class="mt-5 rounded-xl border border-n-weak p-4"><div class="flex items-center justify-between"><div><h4 class="font-semibold">Produtos <i class="i-lucide-pencil ml-1 size-3 text-n-slate-10" /></h4><p class="text-xs text-n-slate-10">Edite quantidade, preço e desconto diretamente no negócio.</p></div><span class="text-xs text-n-slate-10">{{ selectedDeal.products_count || 0 }} item(ns)</span></div><div v-if="editingDetails" class="mt-3 grid gap-2 md:grid-cols-[1fr_80px_110px_110px_auto]"><select v-model="detailsProductForm.product_id" class="rounded-lg border border-n-weak px-2 py-2 text-xs" @change="selectDetailsProduct"><option value="">Produto</option><option v-for="product in products" :key="product.id" :value="product.id">{{ product.name }}</option></select><input v-model.number="detailsProductForm.quantity" type="number" min="1" class="rounded-lg border border-n-weak px-2 py-2 text-xs" placeholder="Qtd" /><input v-model="detailsProductForm.unit_price" type="number" min="0" step="0.01" class="rounded-lg border border-n-weak px-2 py-2 text-xs" placeholder="Preço" /><input v-model="detailsProductForm.discount" type="number" min="0" step="0.01" class="rounded-lg border border-n-weak px-2 py-2 text-xs" placeholder="Desconto" /><button type="button" class="rounded-lg bg-n-brand px-3 py-2 text-xs font-semibold text-white" @click="addDetailsProduct">Adicionar</button></div><table v-if="selectedDeal.deal_products?.length" class="mt-3 min-w-full text-xs"><thead><tr class="border-b border-n-weak"><th class="py-2 text-left">Produto</th><th class="py-2 text-right">Qtd</th><th class="py-2 text-right">Unitário</th><th class="py-2 text-right">Desc.</th><th class="py-2 text-right">Total</th><th v-if="editingDetails"></th></tr></thead><tbody><tr v-for="item in selectedDeal.deal_products" :key="item.id" class="border-b border-n-weak"><td class="py-2">{{ item.product?.name || 'Produto' }}</td><td class="py-2 text-right"><input v-if="editingDetails" v-model.number="item.quantity" type="number" min="1" class="w-16 rounded border border-n-weak px-1 py-1 text-right" @change="updateDetailsProduct(item)" /><span v-else>{{ item.quantity }}</span></td><td class="py-2 text-right"><input v-if="editingDetails" :value="moneyInput(item.unit_price_cents)" type="number" min="0" step="0.01" class="w-24 rounded border border-n-weak px-1 py-1 text-right" @change="item.unit_price_cents = centsFromInput($event.target.value); updateDetailsProduct(item)" /><span v-else>R$ {{ moneyInput(item.unit_price_cents) }}</span></td><td class="py-2 text-right"><input v-if="editingDetails" :value="moneyInput(item.discount_cents)" type="number" min="0" step="0.01" class="w-20 rounded border border-n-weak px-1 py-1 text-right" @change="item.discount_cents = centsFromInput($event.target.value); updateDetailsProduct(item)" /><span v-else>R$ {{ moneyInput(item.discount_cents) }}</span></td><td class="py-2 text-right font-semibold">R$ {{ moneyInput(item.total_cents) }}</td><td v-if="editingDetails" class="py-2 text-right"><button type="button" class="i-lucide-trash-2 text-n-ruby-11" @click="removeDetailsProduct(item)" /></td></tr></tbody></table><p v-else class="mt-3 text-sm text-n-slate-10">Nenhum produto vinculado.</p></section>
        <OperationsLinks :key="selectedDeal.id" :deal-id="selectedDeal.id" :deal-status="selectedDeal.status" :contact-id="selectedDeal.contact_id" :title="selectedDeal.title" compact />
        <button v-if="selectedDeal.conversation" type="button" class="mt-5 w-full rounded-lg bg-n-brand px-4 py-2 font-semibold text-white" @click="openConversation(selectedDeal.conversation)">Voltar à conversa vinculada</button></aside></div>
    </Teleport>
  </div>
</template>
