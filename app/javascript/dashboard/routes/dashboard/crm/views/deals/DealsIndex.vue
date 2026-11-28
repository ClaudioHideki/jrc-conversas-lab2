<script setup>
import { useCustomerSegmentFilter } from '../../helpers/useCustomerSegmentFilter';
import { useQuickActionTarget } from 'dashboard/components-next/layout/useQuickActionTarget';
import OperationsLinks from '../../../jrcOperations/components/OperationsLinks.vue';
import { crmControlClasses } from '../../crmControlClasses';
import ContactPicker from 'dashboard/routes/dashboard/jrcCustomers/components/ContactPicker.vue';
import ContactCreateModal from 'dashboard/routes/dashboard/jrcCustomers/components/ContactCreateModal.vue';
import { useFormDraft } from '../../helpers/useFormDraft';
import { useI18n } from 'vue-i18n';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
const props = defineProps({ creationOnly: { type: Boolean, default: false } });
const emit = defineEmits(['close']);
const { enabled: hasCustomerMaster } = useCustomerMaster();
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import {
  computed,
  nextTick,
  onMounted,
  onBeforeUnmount,
  reactive,
  ref,
  watch,
} from 'vue';
import { useProjects } from '../../../jrcProjects/useProjects';
import { errorMessage } from '../../../jrcOperations/api';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { authorityScope } from 'dashboard/store/crm/authorityScope';
import ContactsAPI from 'dashboard/api/contacts';
import AgentsAPI from 'dashboard/api/agents';
import {
  dealsAPI,
  pipelinesAPI,
  stagesAPI,
  productsAPI,
} from 'dashboard/api/crm';
import { useAlert } from 'dashboard/composables';
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import CrmBadge from '../../components/shared/CrmBadge.vue';
import CrmListingHeader from '../../components/shared/CrmListingHeader.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import { useCommercialLabels } from '../../composables/useCommercialLabels';
import CrmValueDisplay from '../../components/shared/CrmValueDisplay.vue';
import DealWorkspaceDialog from './DealWorkspaceDialog.vue';
import InitialActivityFields from '../../components/shared/InitialActivityFields.vue';

const { projectText } = useProjects();
const { t } = useI18n();
const { statusLabel } = useCommercialLabels();
const store = useStore();
const route = useRoute();
const router = useRouter();
let disposed = false;
let viewGeneration = 0;
let detailGeneration = 0;
let detailViewGeneration = 0;
let stageGeneration = 0;
let metadataGeneration = 0;
const viewIdentity = computed(
  () => `${route.params.accountId}:${authorityScope(store.getters)}`
);
const captureContext = () => ({
  identity: viewIdentity.value,
  generation: viewGeneration,
});
const isCurrentContext = context =>
  !disposed &&
  context.identity === viewIdentity.value &&
  context.generation === viewGeneration;
const isCurrentMetadata = context =>
  isCurrentContext(context) && context.metadata === metadataGeneration;
const metadataError = ref('');
const metadataLoading = ref(false);
const stageError = ref('');
const stageLoading = ref(false);
const { segmentParams, watchSegment } = useCustomerSegmentFilter();
const loadDeals = () =>
  store.dispatch('jrcCrm/deals/fetchDeals', segmentParams());
watchSegment(() => {
  if (!props.creationOnly) return loadDeals();
  return undefined;
});
const showForm = ref(props.creationOnly);
watch(showForm, visible => {
  if (props.creationOnly && !visible) emit('close');
});
const showContactForm = ref(false);
const creationForm = ref(null);
const creationTab = ref(0);
const creationTabs = [
  {
    id: 'information',
    label: 'DEAL_DATA',
    icon: 'i-lucide-info',
  },
  {
    id: 'products',
    label: 'PRODUCTS_VALUES',
    icon: 'i-lucide-package',
  },
  {
    id: 'next-action',
    label: 'NEXT_ACTION',
    icon: 'i-lucide-file-text',
  },
];
const lastCreationTab = creationTabs.length - 1;
const switchCreationTab = async index => {
  creationTab.value = index;
  await nextTick();
  const element = creationForm.value;
  if (!element) return;
  element.scrollTop = 0;
  element.querySelector(`#deal-tab-${creationTabs[index].id}`)?.focus();
};
const navigateCreationTabs = event => {
  const destinations = {
    ArrowLeft: (creationTab.value + lastCreationTab) % creationTabs.length,
    ArrowRight: (creationTab.value + 1) % creationTabs.length,
    Home: 0,
    End: lastCreationTab,
  };
  const index = destinations[event.key];
  if (typeof index !== 'number') return;
  event.preventDefault();
  switchCreationTab(index);
};
const openProposal = id =>
  router.push({
    name: 'crm_proposals',
    params: { accountId: route.params.accountId },
    query: { new: '1', dealId: id },
  });
const saving = ref(false);
const closeForm = () => {
  if (!saving.value && !showContactForm.value) showForm.value = false;
};
const pipelines = ref([]);
const stages = ref([]);
const contacts = ref([]);
const products = ref([]);
const agents = ref([]);
const dealItems = ref([]);
const editingDetails = ref(false);
const detailsSaving = ref(false);
const detailsHydrating = ref(false);
const detailsEditError = ref('');
const itemWorking = ref(false);
const detailsStages = ref([]);
const form = reactive({
  title: '',
  company_id: null,
  contact_id: '',
  conversation_id: '',
  pipeline_id: '',
  stage_id: '',
  value: '',
  source: '',
  expected_close_at: '',
  probability: 30,
  description: '',
  schedule: false,
  owner_id: '',
});
const newActivity = () => ({
  activity_type: 'proposal',
  due_at: '',
  title: '',
  description: '',
});
const activity = ref(newActivity());
const productForm = reactive({
  product_id: '',
  quantity: 1,
  unit_price: '',
  discount: '',
});
const detailsForm = reactive({
  company_id: null,
  contact_id: '',
  stage_id: '',
  owner_id: '',
  source: '',
  value: '',
});
const detailsProductForm = reactive({
  product_id: '',
  quantity: 1,
  unit_price: '',
  discount: '',
});

const sourceOptions = [
  ['whatsapp', 'WhatsApp'],
  ['ligacoes', 'Ligações'],
  ['ligacoes_whatsapp', 'Ligações WhatsApp'],
  ['email', 'E-mail'],
  ['instagram', 'Instagram'],
  ['facebook', 'Facebook'],
  ['webchat', 'Webchat'],
  ['indicacao', 'Indicação'],
  ['campanha', 'Campanha'],
  ['prospeccao_ativa', 'Prospecção ativa'],
  ['outro', 'Outro'],
];

const deals = computed(() => store.getters['jrcCrm/deals/allDeals'] || []);
const listFilters = reactive({
  search: '',
  stage: '',
  owner: '',
  status: '',
  pipeline: '',
  source: '',
});
const moreFilters = ref(false);
const listPage = ref(1);
const perPage = 15;
const visibleStages = computed(() =>
  [
    ...new Map(
      deals.value.map(deal => [
        deal.stage_id || deal.stage?.id,
        deal.stage?.name || deal.stage_name,
      ])
    ).entries(),
  ].filter(([id, name]) => id && name)
);
const visibleOwners = computed(() =>
  [
    ...new Map(
      deals.value.map(deal => [
        deal.owner_id || deal.owner?.id,
        deal.owner?.name || deal.owner_name,
      ])
    ).entries(),
  ]
    .filter(([id, name]) => id && name)
    .sort((a, b) => a[1].localeCompare(b[1]))
);
const availableStatuses = computed(() => [
  ...new Set(deals.value.map(deal => deal.status).filter(Boolean)),
]);
const availableSources = computed(() =>
  [...new Set(deals.value.map(deal => deal.source).filter(Boolean))].sort()
);
const searchKey = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase();
const filteredDeals = computed(() => {
  const { search, stage, owner, status, pipeline, source } = listFilters;
  const term = searchKey(search.trim());
  return deals.value.filter(
    deal =>
      (!stage || String(deal.stage_id || deal.stage?.id) === stage) &&
      (!owner || String(deal.owner_id || deal.owner?.id) === owner) &&
      (!status || deal.status === status) &&
      (!pipeline ||
        String(deal.pipeline_id || deal.pipeline?.id) === pipeline) &&
      (!source || deal.source === source) &&
      (!term ||
        [deal.title, deal.company_name, deal.contact?.name].some(value =>
          searchKey(value).includes(term)
        ))
  );
});
const pagedDeals = computed(() =>
  filteredDeals.value.slice(
    (listPage.value - 1) * perPage,
    listPage.value * perPage
  )
);
watch(listFilters, () => {
  listPage.value = 1;
});
watch(
  () => filteredDeals.value.length,
  total => {
    listPage.value = Math.min(
      listPage.value,
      Math.max(1, Math.ceil(total / perPage))
    );
  }
);
const stageName = deal => deal.stage?.name || deal.stage_name;
const isNegotiation = deal =>
  /negocia|negotiat/.test(searchKey(stageName(deal)));
const stageTone = deal => {
  if (deal.status === 'won') return 'green';
  if (deal.status === 'lost') return 'red';
  if (isNegotiation(deal)) return 'yellow';
  if (/proposta|proposal/.test(searchKey(stageName(deal)))) return 'purple';
  if (/qualifica|qualify/.test(searchKey(stageName(deal)))) return 'green';
  return 'blue';
};
const openDeal = deal =>
  router.push({ query: { ...route.query, dealId: deal.id } });
const dealSummary = computed(() => {
  const opened = deals.value.filter(deal => deal.status === 'open');
  const now = new Date();
  const wonThisMonth = deals.value.filter(deal => {
    if (deal.status !== 'won' || !deal.won_at) return false;
    const date = new Date(deal.won_at);
    return (
      date.getFullYear() === now.getFullYear() &&
      date.getMonth() === now.getMonth()
    );
  }).length;
  return [
    {
      label: t('CRM.LIST_LAYOUT.OPEN_DEALS'),
      value: opened.length,
      icon: 'i-lucide-folder-open',
      tone: 'text-n-blue-11',
    },
    {
      label: t('CRM.LIST_LAYOUT.NEGOTIATING'),
      value: opened.filter(isNegotiation).length,
      icon: 'i-lucide-handshake',
      tone: 'text-n-amber-11',
    },
    {
      label: t('CRM.LIST_LAYOUT.WON_THIS_MONTH'),
      value: wonThisMonth,
      icon: 'i-lucide-trophy',
      tone: 'text-n-teal-11',
    },
    {
      label: t('CRM.LIST_LAYOUT.OPEN_VALUE'),
      value: opened.reduce(
        (sum, deal) => sum + Number(deal.value_cents || 0),
        0
      ),
      money: true,
      icon: 'i-lucide-coins',
      tone: 'text-n-blue-11',
    },
  ];
});
const loading = computed(() => store.getters['jrcCrm/deals/isLoading']);
const error = computed(() => store.getters['jrcCrm/deals/error']);
const detailLoading = ref(false);
const detailError = ref('');
const loadedDetailKey = ref('');
const detailKey = () =>
  `${route.params.accountId}:${authorityScope(store.getters)}:${route.query.dealId || ''}`;
const captureDetailContext = () => ({
  ...captureContext(),
  key: detailKey(),
  selection: detailViewGeneration,
});
const isCurrentDetail = context =>
  isCurrentContext(context) &&
  context.key === detailKey() &&
  context.selection === detailViewGeneration;
const resetDetailsForm = () => {
  Object.assign(detailsForm, {
    company_id: null,
    contact_id: '',
    stage_id: '',
    owner_id: '',
    source: '',
    value: '',
  });
  Object.assign(detailsProductForm, {
    product_id: '',
    quantity: 1,
    unit_price: '',
    discount: '',
  });
  detailsStages.value = [];
  detailsEditError.value = '';
  editingDetails.value = false;
  detailsSaving.value = false;
  detailsHydrating.value = false;
  itemWorking.value = false;
};
const selectedDeal = computed(() => {
  if (props.creationOnly) return null;
  if (
    !route.query.dealId ||
    detailLoading.value ||
    detailError.value ||
    loadedDetailKey.value !== detailKey()
  )
    return null;
  const current = store.getters['jrcCrm/deals/currentDeal'];
  return String(current?.id) === String(route.query.dealId) ? current : null;
});
async function loadDetails() {
  if (props.creationOnly || disposed) return;
  detailGeneration += 1;
  const current = detailGeneration;
  const context = captureDetailContext();
  const dealId = route.query.dealId;
  detailLoading.value = Boolean(dealId);
  detailError.value = '';
  loadedDetailKey.value = '';
  editingDetails.value = false;
  if (!dealId) {
    await store.dispatch('jrcCrm/deals/fetchDeal', null);
    return;
  }
  try {
    await store.dispatch('jrcCrm/deals/fetchDeal', dealId);
    if (current !== detailGeneration || !isCurrentDetail(context)) return;
    detailError.value = store.getters['jrcCrm/deals/detailError'] || '';
    loadedDetailKey.value = context.key;
  } catch (requestError) {
    if (current === detailGeneration && isCurrentDetail(context))
      detailError.value = errorMessage(requestError);
  } finally {
    if (current === detailGeneration && isCurrentDetail(context))
      detailLoading.value = false;
  }
}

const itemsSubtotal = computed(() =>
  dealItems.value.reduce(
    (sum, item) =>
      sum + Number(item.unit_price_cents || 0) * Number(item.quantity || 0),
    0
  )
);
const itemsDiscount = computed(() =>
  dealItems.value.reduce(
    (sum, item) => sum + Number(item.discount_cents || 0),
    0
  )
);
const itemsTotal = computed(() =>
  Math.max(itemsSubtotal.value - itemsDiscount.value, 0)
);

const centsFromInput = value => Math.round(Number(value || 0) * 100);
const moneyInput = cents => (Number(cents || 0) / 100).toFixed(2);
const closeDetails = () => {
  detailViewGeneration += 1;
  detailGeneration += 1;
  loadedDetailKey.value = '';
  detailLoading.value = false;
  detailError.value = '';
  resetDetailsForm();
  const query = { ...route.query };
  delete query.dealId;
  router.replace({ query });
};
const openConversation = conversation =>
  router.push({
    name: 'inbox_conversation',
    params: {
      accountId: route.params.accountId,
      conversation_id: conversation.display_id || conversation.id,
    },
  });

const loadContacts = async context => {
  const { data } = await ContactsAPI.get(1);
  if (isCurrentMetadata(context)) contacts.value = data.payload || [];
};
const loadStages = async () => {
  stageGeneration += 1;
  const request = stageGeneration;
  const context = captureContext();
  const pipelineId = form.pipeline_id;
  stages.value = [];
  stageError.value = '';
  stageLoading.value = Boolean(pipelineId);
  if (!pipelineId || disposed) return;
  try {
    const { data } = await stagesAPI.list({ pipeline_id: pipelineId });
    if (
      !isCurrentContext(context) ||
      request !== stageGeneration ||
      String(pipelineId) !== String(form.pipeline_id)
    )
      return;
    stages.value = data.filter(
      stage => stage.active !== false && !stage.is_terminal
    );
    if (!stages.value.some(stage => String(stage.id) === String(form.stage_id)))
      form.stage_id = stages.value[0]?.id || '';
  } catch {
    if (isCurrentContext(context) && request === stageGeneration)
      stageError.value = t('CRM.DEAL_CREATION.LOAD_ERROR');
  } finally {
    if (isCurrentContext(context) && request === stageGeneration)
      stageLoading.value = false;
  }
};
const loadProducts = async context => {
  const { data } = await productsAPI.list({ active: true });
  if (isCurrentMetadata(context)) products.value = data;
};
const resetForm = () => {
  form.title = '';
  form.company_id = null;
  form.contact_id = '';
  form.conversation_id = '';
  form.value = '';
  form.source = '';
  form.description = '';
  form.expected_close_at = '';
  form.probability = 30;
  form.schedule = false;
  form.owner_id = '';
  form.pipeline_id = pipelines.value[0]?.id || '';
  form.stage_id = '';
  dealItems.value = [];
};
const dealDraft = useFormDraft('crm:new_deal', {
  active: showForm,
  snapshot: () => ({
    form: { ...form },
    activity: { ...activity.value },
    items: dealItems.value.map(item => ({
      product_id: item.product_id,
      product: { id: item.product_id, name: item.product?.name },
      quantity: item.quantity,
      unit_price_cents: item.unit_price_cents,
      discount_cents: item.discount_cents,
    })),
    product: { ...productForm },
  }),
  restore: draft => {
    Object.assign(form, draft.form || {});
    const previousForm = draft.form || {};
    const previousActivity =
      previousForm.next_activity_at && previousForm.next_activity_title;
    if (previousActivity) form.schedule = true;
    activity.value = {
      ...newActivity(),
      ...(previousActivity
        ? {
            activity_type: previousForm.next_activity_type,
            due_at: previousForm.next_activity_at,
            title: previousForm.next_activity_title,
          }
        : draft.activity),
    };
    dealItems.value = draft.items || [];
    Object.assign(productForm, draft.product || {});
  },
  reset: () => {
    resetForm();
    activity.value = newActivity();
    creationTab.value = 0;
    Object.assign(productForm, {
      product_id: '',
      quantity: 1,
      unit_price: '',
      discount: '',
    });
  },
});
const openForm = async () => {
  if (saving.value || disposed) return;
  const restored = dealDraft.open();
  if (!restored) {
    form.contact_id = props.creationOnly ? '' : route.query.contactId || '';
    form.conversation_id = props.creationOnly
      ? ''
      : route.query.conversationId || '';
  } else useAlert(t('CRM.CREATION.RECOVERED'));
  showForm.value = true;
  await loadStages();
};
useQuickActionTarget('crm_deals', openForm);

const contactCreated = contact => {
  if (disposed || !showForm.value || !showContactForm.value) return;
  form.contact_id = contact.id;
  showContactForm.value = false;
};

const selectProduct = () => {
  const product = products.value.find(
    item => String(item.id) === String(productForm.product_id)
  );
  productForm.unit_price = product ? moneyInput(product.unit_price_cents) : '';
};
const addProductDraft = () => {
  const product = products.value.find(
    item => String(item.id) === String(productForm.product_id)
  );
  if (!product) return;
  const quantity = Number(productForm.quantity);
  const price = centsFromInput(productForm.unit_price);
  const discount = centsFromInput(productForm.discount);
  if (
    !Number.isSafeInteger(quantity) ||
    quantity < 1 ||
    price < 0 ||
    discount < 0 ||
    discount > price * quantity
  ) {
    useAlert(t('CRM.SALES_FLOW.INVALID_PRODUCT'));
    return;
  }
  dealItems.value.push({
    product_id: product.id,
    product,
    quantity,
    unit_price_cents: price,
    discount_cents: discount,
  });
  productForm.product_id = '';
  productForm.quantity = 1;
  productForm.unit_price = '';
  productForm.discount = '';
};
const removeProductDraft = index => dealItems.value.splice(index, 1);

const hydrateDetailsForm = async (deal, context) => {
  if (!deal || !isCurrentDetail(context)) return false;
  detailsForm.contact_id = deal.contact_id || '';
  detailsForm.company_id = deal.company_id || null;
  detailsForm.stage_id = deal.stage_id || '';
  detailsForm.owner_id = deal.owner_id || '';
  detailsForm.source = deal.source || '';
  detailsForm.value = moneyInput(deal.value_cents);
  detailsEditError.value = '';
  try {
    const { data } = await stagesAPI.list({ pipeline_id: deal.pipeline_id });
    if (!isCurrentDetail(context)) return false;
    detailsStages.value = data;
    return true;
  } catch {
    if (isCurrentDetail(context)) {
      detailsStages.value = [];
      detailsEditError.value = t('CRM.DEAL_CREATION.LOAD_ERROR');
    }
    return false;
  }
};

const toggleDetailsEdit = async () => {
  if (
    !selectedDeal.value ||
    detailsHydrating.value ||
    detailsSaving.value ||
    itemWorking.value
  )
    return;
  const context = captureDetailContext();
  if (editingDetails.value) {
    editingDetails.value = false;
    return;
  }
  detailsHydrating.value = true;
  try {
    if (
      (await hydrateDetailsForm(selectedDeal.value, context)) &&
      isCurrentDetail(context)
    )
      editingDetails.value = true;
  } finally {
    if (isCurrentDetail(context)) detailsHydrating.value = false;
  }
};

const saveDetails = async () => {
  if (
    !selectedDeal.value ||
    detailsSaving.value ||
    itemWorking.value ||
    detailsHydrating.value
  )
    return;
  const context = captureDetailContext();
  const dealId = selectedDeal.value.id;
  detailsSaving.value = true;
  try {
    await dealsAPI.update(dealId, {
      deal: {
        contact_id: detailsForm.contact_id || null,
        ...(hasCustomerMaster.value
          ? { company_id: detailsForm.company_id }
          : {}),
        stage_id: detailsForm.stage_id,
        owner_id: detailsForm.owner_id || undefined,
        source: detailsForm.source,
        value_cents: centsFromInput(detailsForm.value),
      },
    });
    if (!isCurrentDetail(context)) return;
    await loadDeals();
    if (!isCurrentDetail(context)) return;
    await loadDetails();
    if (!isCurrentDetail(context)) return;
    editingDetails.value = false;
    useAlert('Negócio atualizado com sucesso.');
  } catch (requestError) {
    if (!isCurrentDetail(context)) return;
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível atualizar o negócio.'
    );
  } finally {
    if (isCurrentDetail(context)) detailsSaving.value = false;
  }
};

const selectDetailsProduct = () => {
  const product = products.value.find(
    item => String(item.id) === String(detailsProductForm.product_id)
  );
  detailsProductForm.unit_price = product
    ? moneyInput(product.unit_price_cents)
    : '';
};

const addDetailsProduct = async () => {
  if (
    !selectedDeal.value ||
    !detailsProductForm.product_id ||
    itemWorking.value ||
    detailsSaving.value ||
    detailsHydrating.value
  )
    return;
  const context = captureDetailContext();
  const dealId = selectedDeal.value.id;
  itemWorking.value = true;
  try {
    await dealsAPI.createProduct(dealId, {
      item: {
        product_id: detailsProductForm.product_id,
        quantity: Number(detailsProductForm.quantity || 1),
        unit_price_cents: centsFromInput(detailsProductForm.unit_price),
        discount_cents: centsFromInput(detailsProductForm.discount),
      },
    });
    if (!isCurrentDetail(context)) return;
    detailsProductForm.product_id = '';
    detailsProductForm.quantity = 1;
    detailsProductForm.unit_price = '';
    detailsProductForm.discount = '';
    await loadDeals();
    if (!isCurrentDetail(context)) return;
    await loadDetails();
  } catch (requestError) {
    if (!isCurrentDetail(context)) return;
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível adicionar o produto.'
    );
  } finally {
    if (isCurrentDetail(context)) itemWorking.value = false;
  }
};

const updateDetailsProduct = async item => {
  if (
    !selectedDeal.value ||
    itemWorking.value ||
    detailsSaving.value ||
    detailsHydrating.value ||
    !selectedDeal.value.deal_products?.some(
      row => Number(row.id) === Number(item.id)
    )
  )
    return;
  const context = captureDetailContext();
  const dealId = selectedDeal.value.id;
  itemWorking.value = true;
  try {
    await dealsAPI.updateProduct(dealId, item.id, {
      item: {
        quantity: Number(item.quantity || 1),
        unit_price_cents: Number(item.unit_price_cents || 0),
        discount_cents: Number(item.discount_cents || 0),
      },
    });
    if (!isCurrentDetail(context)) return;
    await loadDeals();
    if (!isCurrentDetail(context)) return;
    await loadDetails();
  } catch {
    if (!isCurrentDetail(context)) return;
    await loadDetails();
    if (isCurrentDetail(context))
      useAlert('Não foi possível atualizar o produto.');
  } finally {
    if (isCurrentDetail(context)) itemWorking.value = false;
  }
};

const removeDetailsProduct = async item => {
  if (
    !selectedDeal.value ||
    itemWorking.value ||
    detailsSaving.value ||
    detailsHydrating.value ||
    !selectedDeal.value.deal_products?.some(
      row => Number(row.id) === Number(item.id)
    )
  )
    return;
  const context = captureDetailContext();
  const dealId = selectedDeal.value.id;
  itemWorking.value = true;
  try {
    await dealsAPI.deleteProduct(dealId, item.id);
    if (!isCurrentDetail(context)) return;
    await loadDeals();
    if (!isCurrentDetail(context)) return;
    await loadDetails();
  } catch {
    if (!isCurrentDetail(context)) return;
    await loadDetails();
    if (isCurrentDetail(context))
      useAlert('Não foi possível remover o produto.');
  } finally {
    if (isCurrentDetail(context)) itemWorking.value = false;
  }
};

const save = async event => {
  if (
    !showForm.value ||
    saving.value ||
    disposed ||
    metadataLoading.value ||
    stageLoading.value ||
    metadataError.value ||
    stageError.value
  )
    return;
  if (creationTab.value !== lastCreationTab) {
    switchCreationTab(creationTab.value + 1);
    return;
  }
  const invalidField = creationForm.value?.querySelector(
    'input:invalid, select:invalid, textarea:invalid'
  );
  if (invalidField) {
    await switchCreationTab(
      Number(invalidField.closest('[role="tabpanel"]').dataset.tabIndex)
    );
    invalidField.reportValidity();
    return;
  }
  const context = captureContext();
  const savingDraftKey = dealDraft.key.value;
  saving.value = true;
  try {
    const { data } = await dealsAPI.create({
      deal: {
        title: form.title,
        ...(store.getters.getCurrentRole === 'administrator' && form.owner_id
          ? { owner_id: form.owner_id }
          : {}),
        ...(hasCustomerMaster.value ? { company_id: form.company_id } : {}),
        contact_id: form.contact_id || null,
        conversation_id: form.conversation_id || null,
        pipeline_id: form.pipeline_id,
        stage_id: form.stage_id,
        value_cents: dealItems.value.length
          ? itemsTotal.value
          : centsFromInput(form.value),
        source: form.source,
        expected_close_at: form.expected_close_at || null,
        probability: Number(form.probability || 0),
        description: form.description,
      },
      items: dealItems.value.map(item => ({
        product_id: item.product_id,
        quantity: item.quantity,
        unit_price_cents: item.unit_price_cents,
        discount_cents: item.discount_cents,
      })),
      ...(form.schedule ? { next_activity: { ...activity.value } } : {}),
    });
    if (!isCurrentContext(context) || !dealDraft.complete(savingDraftKey))
      return;
    showForm.value = false;
    useAlert(t('CRM.SALES_FLOW.DEAL_CREATED'));
    if (event?.submitter?.value === 'proposal') {
      openProposal(data.id);
    } else if (props.creationOnly) {
      router.push({
        name: 'crm_deals',
        params: { accountId: route.params.accountId },
        query: { dealId: data.id },
      });
    } else {
      openDeal(data);
      loadDeals();
    }
  } catch (requestError) {
    if (!isCurrentContext(context)) return;
    useAlert(
      requestError.response?.data?.errors?.join(', ') ||
        'Não foi possível criar o negócio.'
    );
  } finally {
    if (isCurrentContext(context)) saving.value = false;
  }
};
const initialize = async () => {
  if (disposed) return;
  metadataGeneration += 1;
  const context = { ...captureContext(), metadata: metadataGeneration };
  metadataLoading.value = true;
  metadataError.value = '';
  pipelines.value = [];
  contacts.value = [];
  products.value = [];
  agents.value = [];
  stages.value = [];
  try {
    const [pipelinesResponse] = await Promise.all([
      pipelinesAPI.list(),
      loadContacts(context),
      loadProducts(context),
      ...(!props.creationOnly ||
      store.getters.getCurrentRole === 'administrator'
        ? [
            AgentsAPI.get().then(({ data }) => {
              if (isCurrentMetadata(context)) agents.value = data || [];
            }),
          ]
        : []),
      ...(!props.creationOnly ? [loadDeals()] : []),
    ]);
    if (!isCurrentMetadata(context)) return;
    pipelines.value = pipelinesResponse.data;
    if (
      !pipelines.value.some(
        pipeline => String(pipeline.id) === String(form.pipeline_id)
      )
    )
      form.pipeline_id = pipelines.value[0]?.id || '';
    await loadStages();
  } catch {
    if (isCurrentMetadata(context))
      metadataError.value = t('CRM.DEAL_CREATION.LOAD_ERROR');
  } finally {
    if (isCurrentMetadata(context)) metadataLoading.value = false;
  }
};
watch(viewIdentity, () => {
  viewGeneration += 1;
  dealDraft.flush();
  showForm.value = false;
  showContactForm.value = false;
  saving.value = false;
  pipelines.value = [];
  contacts.value = [];
  products.value = [];
  agents.value = [];
  stages.value = [];
  Object.assign(listFilters, {
    search: '',
    stage: '',
    owner: '',
    status: '',
    pipeline: '',
    source: '',
  });
  metadataError.value = '';
  stageError.value = '';
  metadataLoading.value = false;
  stageLoading.value = false;
  resetForm();
  Object.assign(productForm, {
    product_id: '',
    quantity: 1,
    unit_price: '',
    discount: '',
  });
  if (!props.creationOnly) initialize();
});
watch(
  () => [viewIdentity.value, route.query.dealId],
  () => {
    detailViewGeneration += 1;
    resetDetailsForm();
    loadDetails();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  disposed = true;
  viewGeneration += 1;
  detailViewGeneration += 1;
  detailGeneration += 1;
  stageGeneration += 1;
});
watch(() => form.pipeline_id, loadStages);
onMounted(() => {
  if (
    props.creationOnly ||
    route.query.new === '1' ||
    route.query.conversationId ||
    route.query.contactId
  )
    openForm();
  initialize();
});
</script>

<template>
  <div
    :class="
      props.creationOnly
        ? 'contents'
        : 'flex min-h-full min-w-0 flex-col gap-3 bg-gradient-to-b from-n-blue-2 to-n-surface-1 p-3 sm:px-6'
    "
  >
    <template v-if="!props.creationOnly">
      <div v-if="!showForm">
        <div
          v-if="metadataError || stageError"
          role="alert"
          class="rounded-xl border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
        >
          {{ metadataError || stageError }}
          <button type="button" class="ml-2 underline" @click="initialize">
            {{ t('CRM.DEAL_CREATION.RETRY') }}
          </button>
        </div>
      </div>
      <CrmListingHeader :title="t('CRM.NAV.DEALS')">
        <RouterLink
          :to="{ name: 'crm_funnel' }"
          class="inline-flex items-center rounded-lg border border-n-weak bg-n-solid-2 px-3 py-2 text-sm font-semibold text-n-slate-12 shadow-sm"
        >
          {{ t('CRM.LIST_LAYOUT.VIEW_FUNNEL') }}
        </RouterLink>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white shadow-sm"
          @click="openForm"
        >
          <span class="i-lucide-plus size-4" aria-hidden="true" />
          {{ t('CRM.LIST_LAYOUT.NEW_DEAL') }}
        </button>
      </CrmListingHeader>
      <section
        class="grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-n-blue-5 bg-n-blue-5 lg:grid-cols-4"
      >
        <div
          v-for="metric in dealSummary"
          :key="metric.label"
          class="flex min-w-0 items-center gap-2 bg-n-blue-3 px-3 py-2.5"
          :class="metric.tone"
        >
          <span
            :class="metric.icon"
            class="size-4 shrink-0"
            aria-hidden="true"
          />
          <span class="min-w-0 flex-1 text-xs font-semibold">{{
            metric.label
          }}</span>
          <strong class="text-sm tabular-nums">
            <CrmValueDisplay v-if="metric.money" :cents="metric.value" />
            <template v-else>{{ metric.value }}</template>
          </strong>
        </div>
      </section>
      <div
        class="flex flex-wrap items-center gap-2 rounded-xl border border-n-weak bg-n-solid-2 p-2 shadow-sm"
      >
        <label class="relative min-w-[min(100%,15rem)] flex-1">
          <span
            class="i-lucide-search pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-11"
            aria-hidden="true"
          />
          <input
            v-model="listFilters.search"
            type="search"
            :placeholder="t('CRM.LIST_LAYOUT.DEALS_SEARCH')"
            :aria-label="t('CRM.LIST_LAYOUT.DEALS_SEARCH')"
            class="reset-base m-0 h-9 w-full rounded-lg border border-n-weak bg-n-solid-1 pe-3 ps-9 text-sm"
          />
        </label>
        <select
          v-model="listFilters.stage"
          :aria-label="t('CRM.LIST_LAYOUT.STAGE')"
          class="!mb-0 h-9 w-auto min-w-28 max-w-full !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
        >
          <option value="">{{ t('CRM.LIST_LAYOUT.STAGE') }}</option>
          <option
            v-for="[id, name] in visibleStages"
            :key="id"
            :value="String(id)"
          >
            {{ name }}
          </option>
        </select>
        <select
          v-model="listFilters.owner"
          :aria-label="t('CRM.LIST_LAYOUT.OWNER')"
          class="!mb-0 h-9 w-auto min-w-32 max-w-full !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
        >
          <option value="">{{ t('CRM.LIST_LAYOUT.OWNER') }}</option>
          <option
            v-for="[id, name] in visibleOwners"
            :key="id"
            :value="String(id)"
          >
            {{ name }}
          </option>
        </select>
        <select
          v-model="listFilters.status"
          :aria-label="t('CRM.LIST_LAYOUT.STATUS')"
          class="!mb-0 h-9 w-auto min-w-28 !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
        >
          <option value="">{{ t('CRM.LIST_LAYOUT.STATUS') }}</option>
          <option
            v-for="status in availableStatuses"
            :key="status"
            :value="status"
          >
            {{ statusLabel(status) }}
          </option>
        </select>
        <button
          type="button"
          :aria-expanded="moreFilters"
          class="inline-flex h-9 items-center gap-2 rounded-lg border border-n-weak px-3 text-xs font-semibold text-n-blue-11"
          @click="moreFilters = !moreFilters"
        >
          <span class="i-lucide-list-filter size-4" aria-hidden="true" />
          {{ t('CRM.DIRECTORY.MORE_FILTERS') }}
        </button>
        <div
          v-if="moreFilters"
          class="flex w-full flex-wrap gap-2 border-t border-n-weak pt-2"
        >
          <select
            v-model="listFilters.pipeline"
            :aria-label="t('CRM.LIST_LAYOUT.PIPELINE')"
            class="!mb-0 h-9 w-auto min-w-28 max-w-full !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
          >
            <option value="">{{ t('CRM.LIST_LAYOUT.PIPELINE') }}</option>
            <option
              v-for="pipeline in pipelines"
              :key="pipeline.id"
              :value="String(pipeline.id)"
            >
              {{ pipeline.name }}
            </option>
          </select>
          <select
            v-model="listFilters.source"
            :aria-label="t('CRM.LIST_LAYOUT.SOURCE')"
            class="!mb-0 h-9 w-auto min-w-28 !appearance-auto rounded-lg border border-n-weak bg-n-solid-1 !bg-none px-2 text-sm"
          >
            <option value="">{{ t('CRM.LIST_LAYOUT.SOURCE') }}</option>
            <option
              v-for="source in availableSources"
              :key="source"
              :value="source"
            >
              {{ source }}
            </option>
          </select>
        </div>
      </div>
      <section
        class="min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-solid-2 shadow-sm"
      >
        <div class="relative overflow-x-auto">
          <table
            class="w-full min-w-[780px] text-sm"
            :aria-label="t('CRM.LIST_LAYOUT.DEALS_LIST')"
          >
            <thead
              class="bg-n-slate-3 text-left text-[11px] uppercase tracking-wide text-n-slate-11"
            >
              <tr>
                <th scope="col" class="px-4 py-2">
                  {{ t('CRM.LIST_LAYOUT.DEAL_NAME') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.STAGE') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.VALUE') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.OWNER') }}
                </th>
                <th scope="col" class="px-3 py-2">
                  {{ t('CRM.LIST_LAYOUT.STATUS') }}
                </th>
                <th scope="col" class="px-4 py-2 text-right">
                  {{ t('CRM.CONTACT_LEAD.UI.ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-n-weak">
              <tr v-if="loading">
                <td colspan="6" class="px-5 py-10 text-center text-n-slate-11">
                  {{ t('CRM.LIST_LAYOUT.LOADING_DEALS') }}
                </td>
              </tr>
              <tr v-else-if="error">
                <td colspan="6" class="px-5 py-10 text-center text-n-ruby-11">
                  {{ error }}
                </td>
              </tr>
              <tr v-else-if="!pagedDeals.length">
                <td colspan="6" class="px-5 py-10 text-center text-n-slate-11">
                  {{ t('CRM.LIST_LAYOUT.NO_DEALS') }}
                </td>
              </tr>
              <tr
                v-for="deal in pagedDeals"
                :key="deal.id"
                class="cursor-pointer hover:bg-n-blue-2"
                @click="openDeal(deal)"
              >
                <td class="min-w-48 px-4 py-1.5">
                  <p class="m-0 font-semibold leading-tight text-n-slate-12">
                    {{ deal.title }}
                  </p>
                  <p class="m-0 text-xs text-n-slate-11">
                    {{
                      deal.company_name ||
                      deal.contact?.name ||
                      t('CRM.LIST_LAYOUT.NO_CONTACT')
                    }}
                  </p>
                </td>
                <td class="px-3 py-1.5">
                  <CrmBadge v-if="stageName(deal)" :color="stageTone(deal)">{{
                    stageName(deal)
                  }}</CrmBadge>
                  <span v-else>{{ '—' }}</span>
                </td>
                <td
                  class="whitespace-nowrap px-3 py-1.5 font-semibold tabular-nums"
                >
                  <CrmValueDisplay :cents="deal.value_cents" />
                </td>
                <td class="px-3 py-1.5 text-xs text-n-slate-11">
                  <div
                    v-if="deal.owner?.name || deal.owner_name"
                    class="flex items-center gap-2 whitespace-nowrap"
                  >
                    <Avatar
                      :name="deal.owner?.name || deal.owner_name"
                      :size="24"
                      rounded-full
                    />
                    {{ deal.owner?.name || deal.owner_name }}
                  </div>
                  <span v-else>{{ t('CRM.LIST_LAYOUT.UNASSIGNED') }}</span>
                </td>
                <td class="px-3 py-1.5">
                  <CrmStatusBadge :value="deal.status" />
                </td>
                <td class="px-4 py-1.5 text-right">
                  <button
                    type="button"
                    :title="t('CRM.LIST_LAYOUT.OPEN_DEAL')"
                    class="inline-flex h-7 items-center gap-1 rounded-md border border-n-blue-6 bg-n-blue-2 px-2 text-xs font-semibold text-n-blue-11"
                    @click.stop="openDeal(deal)"
                  >
                    <span
                      class="i-lucide-external-link size-3.5"
                      aria-hidden="true"
                    />
                    {{ t('CRM.LIST_LAYOUT.OPEN') }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <PaginationFooter
          v-if="filteredDeals.length"
          :current-page="listPage"
          :items-per-page="perPage"
          :total-items="filteredDeals.length"
          current-page-info="CRM.LIST_LAYOUT.SHOWING_DEALS"
          numbered
          @update:current-page="listPage = $event"
        />
      </section>
    </template>
    <Teleport to="body">
      <div
        v-if="
          !props.creationOnly &&
          route.query.dealId &&
          (detailLoading || detailError)
        "
        class="fixed inset-0 z-[80] flex justify-end bg-black/40"
        @click.self="closeDetails"
      >
        <aside
          class="h-full w-full max-w-2xl overflow-auto bg-n-solid-2 p-6 shadow-2xl"
        >
          <button
            class="mb-4 rounded-lg border border-n-weak px-3 py-2"
            @click="closeDetails"
          >
            {{ projectText('CLOSE_RELATED', 'Fechar') }}
          </button>
          <p v-if="detailLoading" role="status">
            {{ projectText('RELATED_DEAL_LOADING', 'Carregando negócio...') }}
          </p>
          <div v-else role="alert">
            <p>{{ detailError }}</p>
            <button
              class="mt-4 rounded-lg border border-n-weak px-3 py-2"
              @click="loadDetails"
            >
              {{ projectText('RETRY', 'Tentar novamente') }}
            </button>
          </div>
        </aside>
      </div>
      <div
        v-if="showForm"
        :class="crmControlClasses"
        class="fixed inset-0 z-[80] flex items-center justify-center bg-black/45 p-4"
        @click.self="closeForm"
        @keydown.esc="closeForm"
      >
        <form
          ref="creationForm"
          role="dialog"
          aria-modal="true"
          aria-labelledby="deal-create-title"
          novalidate
          class="max-h-[94vh] w-full max-w-4xl overflow-auto rounded-2xl bg-n-solid-2 p-6 shadow-2xl"
          @submit.prevent="save"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <div class="flex items-center gap-3">
                <span
                  class="grid size-11 place-content-center rounded-xl bg-blue-700 text-white"
                  ><i class="i-lucide-briefcase-business size-5"
                /></span>
                <div>
                  <h3
                    id="deal-create-title"
                    class="text-xl font-bold text-n-slate-12"
                  >
                    {{ t('CRM.SALES_FLOW.NEW_DEAL_TITLE') }}
                  </h3>
                  <p class="text-xs text-n-slate-9">
                    Registre uma nova oportunidade comercial
                  </p>
                </div>
              </div>
              <p
                v-if="form.conversation_id"
                class="mt-2 text-xs text-n-teal-11"
              >
                Criando a partir da conversa #{{ form.conversation_id }}.
              </p>
            </div>
            <button
              type="button"
              :aria-label="t('CRM.CREATION.CLOSE')"
              class="i-lucide-x size-5"
              @click="closeForm"
            />
          </div>
          <div
            role="tablist"
            class="my-5 grid gap-2 text-sm font-semibold sm:grid-cols-3"
            :aria-label="t('CRM.SALES_FLOW.DEAL_DATA')"
            @keydown="navigateCreationTabs"
          >
            <button
              v-for="(tab, index) in creationTabs"
              :id="`deal-tab-${tab.id}`"
              :key="tab.id"
              type="button"
              role="tab"
              :aria-selected="creationTab === index"
              :aria-controls="`deal-panel-${tab.id}`"
              :tabindex="creationTab === index ? 0 : -1"
              :class="
                creationTab === index
                  ? 'border-n-brand bg-n-brand text-white'
                  : 'border-n-weak bg-n-solid-2 text-n-slate-11 hover:bg-n-slate-3'
              "
              class="flex items-center gap-2 rounded-xl border px-3 py-2.5 text-left"
              :disabled="saving"
              @click="switchCreationTab(index)"
            >
              <i :class="tab.icon" class="size-4" />
              {{ t(`CRM.SALES_FLOW.${tab.label}`) }}
            </button>
          </div>
          <div
            v-if="metadataError || stageError"
            role="alert"
            class="rounded-xl border border-n-ruby-6 bg-n-ruby-3 p-3 text-sm text-n-ruby-11"
          >
            {{ metadataError || stageError }}
            <button type="button" class="ml-2 underline" @click="initialize">
              {{ t('CRM.DEAL_CREATION.RETRY') }}
            </button>
          </div>
          <section
            v-show="creationTab === 0"
            id="deal-panel-information"
            role="tabpanel"
            aria-labelledby="deal-tab-information"
            data-tab-index="0"
            tabindex="0"
            class="rounded-2xl border border-n-weak p-4"
          >
            <h4
              class="mb-3 flex items-center gap-2 font-semibold text-n-slate-12"
            >
              <i class="i-lucide-info size-4 text-blue-600" />Informações da
              oportunidade
            </h4>
            <div class="grid gap-3 md:grid-cols-2">
              <label class="text-xs font-semibold"
                >Título do negócio *<input
                  v-model="form.title"
                  required
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                  placeholder="Ex.: STIR/SHAKEN" /></label
              ><CompanyPicker
                v-if="hasCustomerMaster"
                v-model="form.company_id"
                class="col-span-full"
                @selected="form.contact_id = ''"
              />
              <div class="text-xs font-semibold">
                <span>{{ t('CRM.CREATION.CONTACT') }}</span>
                <ContactPicker
                  v-model="form.contact_id"
                  :company-id="hasCustomerMaster ? form.company_id : null"
                  browse-company
                  @selected="
                    person => {
                      if (!form.company_id && person?.company_id)
                        form.company_id = person.company_id;
                    }
                  "
                />
                <button
                  type="button"
                  class="mt-2 rounded-lg border border-n-weak px-3 py-2"
                  @click="showContactForm = true"
                >
                  {{ t('CRM.CREATION.NEW_CONTACT') }}
                </button>
              </div>
              <label class="text-xs font-semibold"
                >Funil *<select
                  v-model="form.pipeline_id"
                  required
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                  @change="loadStages"
                >
                  <option
                    v-for="pipeline in pipelines"
                    :key="pipeline.id"
                    :value="pipeline.id"
                  >
                    {{ pipeline.name }}
                  </option>
                </select></label
              ><label class="text-xs font-semibold"
                >Etapa *<select
                  v-model="form.stage_id"
                  required
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option
                    v-for="stage in stages"
                    :key="stage.id"
                    :value="stage.id"
                  >
                    {{ stage.name }}
                  </option>
                </select></label
              ><label class="text-xs font-semibold"
                >Origem<select
                  v-model="form.source"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option value="">Sem origem</option>
                  <option
                    v-for="source in sourceOptions"
                    :key="source[0]"
                    :value="source[0]"
                  >
                    {{ source[1] }}
                  </option>
                </select></label
              ><label
                v-if="store.getters.getCurrentRole === 'administrator'"
                class="text-xs font-semibold"
              >
                <span>{{ t('CRM.SALES_FLOW.OWNER') }}</span>
                <select
                  v-model="form.owner_id"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option value="">
                    {{ t('CRM.SALES_FLOW.CURRENT_USER') }}
                  </option>
                  <option
                    v-for="agent in agents"
                    :key="agent.id"
                    :value="agent.id"
                  >
                    {{ agent.name || agent.email }}
                  </option>
                </select> </label
              ><label class="text-xs font-semibold"
                >Probabilidade<select
                  v-model.number="form.probability"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option
                    v-for="p in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]"
                    :key="p"
                    :value="p"
                  >
                    {{ p }}%
                  </option>
                </select></label
              ><label class="text-xs font-semibold"
                >Previsão de fechamento<input
                  v-model="form.expected_close_at"
                  type="date"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2" /></label
              ><label class="text-xs font-semibold md:col-span-2"
                >Observações<textarea
                  v-model="form.description"
                  rows="2"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                  placeholder="Histórico, requisitos e próximos passos…"
                />
              </label>
            </div>
          </section>
          <section
            v-show="creationTab === 1"
            id="deal-panel-products"
            role="tabpanel"
            aria-labelledby="deal-tab-products"
            data-tab-index="1"
            tabindex="0"
            class="mt-4 rounded-2xl border border-n-weak p-4"
          >
            <h4
              class="mb-3 flex items-center gap-2 font-semibold text-n-slate-12"
            >
              <i class="i-lucide-package-plus size-4 text-violet-600" />Produtos
              e valores
            </h4>
            <div class="grid gap-2 md:grid-cols-[1.5fr_80px_130px_120px_auto]">
              <select
                v-model="productForm.product_id"
                class="rounded-lg border border-n-weak px-3 py-2 text-sm"
                @change="selectProduct"
              >
                <option value="">Selecionar produto</option>
                <option
                  v-for="product in products"
                  :key="product.id"
                  :value="product.id"
                >
                  {{ product.name }}
                </option></select
              ><input
                v-model.number="productForm.quantity"
                type="number"
                min="1"
                class="rounded-lg border border-n-weak px-2 py-2"
                placeholder="Qtd"
              /><input
                v-model="productForm.unit_price"
                type="number"
                min="0"
                step="0.01"
                class="rounded-lg border border-n-weak px-2 py-2"
                placeholder="Preço"
              /><input
                v-model="productForm.discount"
                type="number"
                min="0"
                step="0.01"
                class="rounded-lg border border-n-weak px-2 py-2"
                placeholder="Desconto"
              /><button
                type="button"
                class="rounded-lg bg-blue-700 px-3 py-2 text-sm font-semibold text-white"
                @click="addProductDraft"
              >
                + Adicionar
              </button>
            </div>
            <div v-if="dealItems.length" class="mt-4 overflow-auto">
              <table class="min-w-full text-sm">
                <thead>
                  <tr
                    class="border-b border-n-weak text-left text-xs uppercase text-n-slate-10"
                  >
                    <th class="py-2">Produto</th>
                    <th class="py-2 text-right">Qtd</th>
                    <th class="py-2 text-right">Unitário</th>
                    <th class="py-2 text-right">Desconto</th>
                    <th class="py-2 text-right">Total</th>
                    <th />
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(item, index) in dealItems"
                    :key="`${item.product_id}-${index}`"
                    class="border-b border-n-weak"
                  >
                    <td class="py-2">{{ item.product.name }}</td>
                    <td class="py-2 text-right">{{ item.quantity }}</td>
                    <td class="py-2 text-right">
                      R$ {{ moneyInput(item.unit_price_cents) }}
                    </td>
                    <td class="py-2 text-right">
                      R$ {{ moneyInput(item.discount_cents) }}
                    </td>
                    <td class="py-2 text-right font-semibold">
                      R$
                      {{
                        moneyInput(
                          item.unit_price_cents * item.quantity -
                            item.discount_cents
                        )
                      }}
                    </td>
                    <td class="text-right">
                      <button
                        type="button"
                        class="i-lucide-trash-2 text-red-500"
                        @click="removeProductDraft(index)"
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
              <div class="ml-auto mt-3 grid max-w-xs gap-1 text-sm">
                <div class="flex justify-between">
                  <span>Subtotal</span
                  ><strong>R$ {{ moneyInput(itemsSubtotal) }}</strong>
                </div>
                <div class="flex justify-between">
                  <span>Desconto</span
                  ><strong>R$ {{ moneyInput(itemsDiscount) }}</strong>
                </div>
                <div
                  class="flex justify-between border-t border-n-weak pt-2 text-lg"
                >
                  <span>Valor total</span
                  ><strong class="text-emerald-600"
                    >R$ {{ moneyInput(itemsTotal) }}</strong
                  >
                </div>
              </div>
            </div>
            <input
              v-else
              v-model="form.value"
              type="number"
              min="0"
              step="0.01"
              placeholder="Valor do negócio (R$)"
              class="mt-3 w-full rounded-lg border border-n-weak px-3 py-2"
            />
          </section>
          <section
            v-show="creationTab === 2"
            id="deal-panel-next-action"
            role="tabpanel"
            aria-labelledby="deal-tab-next-action"
            data-tab-index="2"
            tabindex="0"
            class="mt-4 space-y-3 rounded-2xl border border-n-teal-5 bg-n-teal-2 p-4"
          >
            <h4 class="flex items-center gap-2 font-semibold text-n-slate-12">
              <i class="i-lucide-file-text size-4 text-n-teal-11" />{{
                t('CRM.SALES_FLOW.NEXT_ACTION')
              }}
            </h4>
            <p class="text-sm text-n-slate-11">
              {{ t('CRM.SALES_FLOW.PROPOSAL_HINT') }}
            </p>
            <label class="flex items-center gap-2 text-sm font-semibold">
              <input v-model="form.schedule" type="checkbox" />{{
                t('CRM.SALES_FLOW.SCHEDULE')
              }}
            </label>
            <InitialActivityFields v-if="form.schedule" v-model="activity" />
          </section>
          <div class="mt-5 flex flex-wrap justify-end gap-2">
            <button
              type="button"
              class="mr-auto rounded-lg border border-n-weak px-3 py-2 text-sm"
              :disabled="saving"
              @click="dealDraft.discard"
            >
              {{ t('CRM.CREATION.DISCARD') }}
            </button>
            <button
              type="button"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm"
              :disabled="saving"
              @click="closeForm"
            >
              {{ t('CRM.CANCEL') }}
            </button>
            <button
              v-if="creationTab > 0"
              type="button"
              class="rounded-lg border border-n-weak px-3 py-2 text-sm font-semibold"
              :disabled="saving"
              @click="switchCreationTab(creationTab - 1)"
            >
              {{ t('CRM.SALES_FLOW.BACK_TAB') }}
            </button>
            <button
              v-if="creationTab < lastCreationTab"
              type="button"
              class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white"
              @click="switchCreationTab(creationTab + 1)"
            >
              {{ t('CRM.SALES_FLOW.NEXT_TAB') }}
            </button>
            <button
              v-if="creationTab === lastCreationTab"
              type="submit"
              :disabled="
                saving ||
                metadataLoading ||
                stageLoading ||
                Boolean(metadataError || stageError)
              "
              class="rounded-lg border border-n-blue-8 px-3 py-2 text-sm font-semibold text-n-blue-11 disabled:opacity-50"
            >
              {{ t('CRM.SALES_FLOW.CREATE_AND_OPEN') }}
            </button>
            <button
              v-if="creationTab === lastCreationTab"
              type="submit"
              value="proposal"
              :disabled="
                saving ||
                metadataLoading ||
                stageLoading ||
                Boolean(metadataError || stageError)
              "
              class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            >
              {{ t('CRM.SALES_FLOW.CREATE_AND_PROPOSE') }}
            </button>
          </div>
        </form>
      </div>

      <DealWorkspaceDialog
        v-if="selectedDeal"
        :key="selectedDeal.id"
        :deal="selectedDeal"
        :editing="editingDetails"
        :editing-busy="detailsHydrating || detailsSaving || itemWorking"
        @close="closeDetails"
        @edit="toggleDetailsEdit"
        @refresh="loadDetails"
        @proposal="openProposal(selectedDeal.id)"
        @conversation="openConversation(selectedDeal.conversation)"
      >
        <template #editor>
          <p
            v-if="detailsEditError"
            role="alert"
            class="mt-3 text-sm text-n-ruby-11"
          >
            {{ detailsEditError }}
          </p>
          <form
            v-if="editingDetails"
            class="mt-6 space-y-4 rounded-xl border border-n-weak p-4"
            @submit.prevent="saveDetails"
          >
            <div class="grid gap-3 md:grid-cols-2">
              <CompanyPicker
                v-if="hasCustomerMaster"
                v-model="detailsForm.company_id"
                class="col-span-full"
              />
              <label class="text-sm font-medium"
                >Cliente<select
                  v-model="detailsForm.contact_id"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option value="">Sem cliente</option>
                  <option
                    v-for="contact in contacts"
                    :key="contact.id"
                    :value="contact.id"
                  >
                    {{ contact.name || contact.email || contact.phone_number }}
                  </option>
                </select></label
              ><label class="text-sm font-medium"
                >Responsável<select
                  v-model="detailsForm.owner_id"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option
                    v-for="agent in agents"
                    :key="agent.id"
                    :value="agent.id"
                  >
                    {{ agent.name || agent.email }}
                  </option>
                </select></label
              ><label class="text-sm font-medium"
                >Etapa<select
                  v-model="detailsForm.stage_id"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option
                    v-for="stage in detailsStages"
                    :key="stage.id"
                    :value="stage.id"
                  >
                    {{ stage.name }}
                  </option>
                </select></label
              ><label class="text-sm font-medium"
                >Origem<select
                  v-model="detailsForm.source"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
                >
                  <option value="">Sem origem</option>
                  <option
                    v-for="source in sourceOptions"
                    :key="source[0]"
                    :value="source[0]"
                  >
                    {{ source[1] }}
                  </option>
                </select></label
              ><label class="text-sm font-medium md:col-span-2"
                >Valor do negócio (R$)<input
                  v-model="detailsForm.value"
                  type="number"
                  min="0"
                  step="0.01"
                  class="mt-1 w-full rounded-lg border border-n-weak px-3 py-2"
              /></label>
            </div>
            <div class="flex justify-end">
              <button
                :disabled="detailsSaving || itemWorking || detailsHydrating"
                class="rounded-lg bg-n-brand px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                <i class="i-lucide-save mr-1" /> Salvar alterações
              </button>
            </div>
          </form>
        </template>
        <template #products>
          <section class="mt-5 rounded-xl border border-n-weak p-4">
            <div class="flex items-center justify-between">
              <div>
                <h4 class="font-semibold">
                  Produtos
                  <i class="i-lucide-pencil ml-1 size-3 text-n-slate-10" />
                </h4>
                <p class="text-xs text-n-slate-10">
                  Edite quantidade, preço e desconto diretamente no negócio.
                </p>
              </div>
              <span class="text-xs text-n-slate-10"
                >{{ selectedDeal.products_count || 0 }} item(ns)</span
              >
            </div>
            <div
              v-if="editingDetails"
              class="mt-3 grid gap-2 md:grid-cols-[1fr_80px_110px_110px_auto]"
            >
              <select
                v-model="detailsProductForm.product_id"
                class="rounded-lg border border-n-weak px-2 py-2 text-xs"
                @change="selectDetailsProduct"
              >
                <option value="">Produto</option>
                <option
                  v-for="product in products"
                  :key="product.id"
                  :value="product.id"
                >
                  {{ product.name }}
                </option></select
              ><input
                v-model.number="detailsProductForm.quantity"
                type="number"
                min="1"
                class="rounded-lg border border-n-weak px-2 py-2 text-xs"
                placeholder="Qtd"
              /><input
                v-model="detailsProductForm.unit_price"
                type="number"
                min="0"
                step="0.01"
                class="rounded-lg border border-n-weak px-2 py-2 text-xs"
                placeholder="Preço"
              /><input
                v-model="detailsProductForm.discount"
                type="number"
                min="0"
                step="0.01"
                class="rounded-lg border border-n-weak px-2 py-2 text-xs"
                placeholder="Desconto"
              /><button
                type="button"
                class="rounded-lg bg-n-brand px-3 py-2 text-xs font-semibold text-white"
                :disabled="itemWorking || detailsSaving || detailsHydrating"
                @click="addDetailsProduct"
              >
                Adicionar
              </button>
            </div>
            <table
              v-if="selectedDeal.deal_products?.length"
              class="mt-3 min-w-full text-xs"
            >
              <thead>
                <tr class="border-b border-n-weak">
                  <th class="py-2 text-left">Produto</th>
                  <th class="py-2 text-right">Qtd</th>
                  <th class="py-2 text-right">Unitário</th>
                  <th class="py-2 text-right">Desc.</th>
                  <th class="py-2 text-right">Total</th>
                  <th v-if="editingDetails" />
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="item in selectedDeal.deal_products"
                  :key="item.id"
                  class="border-b border-n-weak"
                >
                  <td class="py-2">{{ item.product?.name || 'Produto' }}</td>
                  <td class="py-2 text-right">
                    <input
                      v-if="editingDetails"
                      v-model.number="item.quantity"
                      :disabled="itemWorking || detailsSaving"
                      type="number"
                      min="1"
                      class="w-16 rounded border border-n-weak px-1 py-1 text-right"
                      @change="updateDetailsProduct(item)"
                    /><span v-else>{{ item.quantity }}</span>
                  </td>
                  <td class="py-2 text-right">
                    <input
                      v-if="editingDetails"
                      :value="moneyInput(item.unit_price_cents)"
                      :disabled="itemWorking || detailsSaving"
                      type="number"
                      min="0"
                      step="0.01"
                      class="w-24 rounded border border-n-weak px-1 py-1 text-right"
                      @change="
                        item.unit_price_cents = centsFromInput(
                          $event.target.value
                        );
                        updateDetailsProduct(item);
                      "
                    /><span v-else
                      >R$ {{ moneyInput(item.unit_price_cents) }}</span
                    >
                  </td>
                  <td class="py-2 text-right">
                    <input
                      v-if="editingDetails"
                      :value="moneyInput(item.discount_cents)"
                      :disabled="itemWorking || detailsSaving"
                      type="number"
                      min="0"
                      step="0.01"
                      class="w-20 rounded border border-n-weak px-1 py-1 text-right"
                      @change="
                        item.discount_cents = centsFromInput(
                          $event.target.value
                        );
                        updateDetailsProduct(item);
                      "
                    /><span v-else
                      >R$ {{ moneyInput(item.discount_cents) }}</span
                    >
                  </td>
                  <td class="py-2 text-right font-semibold">
                    R$ {{ moneyInput(item.total_cents) }}
                  </td>
                  <td v-if="editingDetails" class="py-2 text-right">
                    <button
                      type="button"
                      class="i-lucide-trash-2 text-n-ruby-11"
                      :disabled="itemWorking || detailsSaving"
                      @click="removeDetailsProduct(item)"
                    />
                  </td>
                </tr>
              </tbody>
            </table>
            <p v-else class="mt-3 text-sm text-n-slate-10">
              Nenhum produto vinculado.
            </p>
          </section>
          <OperationsLinks
            :key="selectedDeal.id"
            :deal-id="selectedDeal.id"
            :deal-status="selectedDeal.status"
            :contact-id="selectedDeal.contact_id"
            :title="selectedDeal.title"
            compact
          />
        </template>
      </DealWorkspaceDialog>
    </Teleport>
  </div>
  <ContactCreateModal
    v-if="showForm && showContactForm"
    :company-id="form.company_id"
    @close="showContactForm = false"
    @created="contactCreated"
  />
</template>
