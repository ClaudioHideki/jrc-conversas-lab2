<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import AgentsAPI from 'dashboard/api/agents';
import {
  backofficeAPI,
  invoicesAPI,
  paymentsAPI,
  salesOrdersAPI,
} from 'dashboard/api/crm/commercialCycle';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const route = useRoute();
const router = useRouter();
const store = useStore();
const tabs = [
  ['overview', 'Visão geral'],
  ['mine', 'Minhas tarefas'],
  ['requests', 'Solicitações'],
  ['process', 'Pedidos para processar'],
  ['docs', 'Documentação'],
  ['contracts', t('CRM.HOMOLOGATION.CONTRACTS')],
  ['implement', 'Implantações'],
  ['provision', 'Provisionamento'],
  ['finance', 'Financeiro'],
  ['issues', 'Pendências'],
  ['approvals', 'Aprovações'],
  ['changes', 'Cancelamentos e alterações'],
  ['sla', 'SLA e filas'],
  ['reports', 'Relatórios'],
];
const validSections = tabs.map(([key]) => key);
const tab = ref(
  validSections.includes(route.params.section)
    ? route.params.section
    : 'overview'
);
const requests = ref([]);
const orders = ref([]);
const invoices = ref([]);
const selectedInvoice = ref(null);
const paymentAmount = ref('');
const invoiceOrderId = ref('');
const invoiceDueOn = ref(new Date(Date.now() + 30 * 86400000).toISOString().slice(0,10));
const eligibleInvoiceOrders = computed(() => orders.value.filter(order =>
  ['approved','separating','invoiced','shipped','completed'].includes(order.status) &&
  !invoices.value.some(invoice => invoice.order?.id === order.id && invoice.status !== 'canceled')
));
const selectableRequests = computed(() => requests.value.filter(request => !['completed','canceled','rejected'].includes(request.status)));
const documentRequests = computed(() => selectableRequests.value.filter(request => ['documentation','contract'].includes(request.stage) || request.documents?.length));
const selectRequest = event => {
  const request = requests.value.find(item => String(item.id) === event.target.value);
  if (request) openRequest(request);
  else selected.value = null;
};
const openContract = () => router.push({ name:'crm_contracts', query:{ contractId:selected.value.contract.id } });
const continueRequest = async () => {
  if (!selected.value) return;
  const section = Object.entries(stageByTab).find(([,stages]) => stages.includes(selected.value.stage))?.[0] || 'requests';
  await router.push({ name:'crm_backoffice', params:{ accountId:route.params.accountId, section } });
};
const summary = ref({});
const agents = ref([]);
const statusFilter = ref('all');
const priorityFilter = ref('all');
const ownerFilter = ref('all');
const documentFiles = ref([]);
const issueDescription = ref('');
const issueType = ref('operational');
const issueDueAt = ref('');
const provisioningMode = ref('manual');
const provisioningExternalReference = ref('');
const provisioningConfirmed = ref(false);
const selected = ref(null);
const loading = ref(false);
const saving = ref(false);
const search = ref('');
const showForm = ref(false);
const form = reactive({
  sales_order_id: '',
  request_kind: 'change',
  priority: 'normal',
  title: '',
  description: '',
  due_at: '',
});

const stageByTab = {
  process: ['request', 'analysis'],
  docs: ['documentation', 'contract'],
  contracts: ['contract'],
  implement: ['implementation'],
  provision: ['provisioning'],
  finance: ['finance'],
  issues: ['issues'],
};

const isOverdue = item =>
  item.due_at &&
  new Date(item.due_at) < new Date() &&
  !['completed', 'canceled', 'rejected'].includes(item.status);

const filteredRequests = computed(() => {
  let rows = requests.value;
  if (tab.value === 'approvals') {
    rows = rows.filter(item => item.request_kind === 'approval' || item.stage === 'approval');
  }
  if (stageByTab[tab.value]) {
    rows = rows.filter(item => stageByTab[tab.value].includes(item.stage));
  }
  if (tab.value === 'changes') {
    rows = rows.filter(item =>
      ['change', 'cancellation'].includes(item.request_kind)
    );
  }
  if (tab.value === 'mine') {
    const currentUserId = store.getters.getCurrentUser?.id;
    rows = rows.filter(item => Number(item.owner?.id) === Number(currentUserId));
  }
  if (tab.value === 'sla') {
    rows = rows.filter(item => isOverdue(item));
  }
  if (statusFilter.value !== 'all') {
    rows = rows.filter(item => item.status === statusFilter.value);
  }
  if (priorityFilter.value !== 'all') {
    rows = rows.filter(item => item.priority === priorityFilter.value);
  }
  if (ownerFilter.value !== 'all') {
    rows = rows.filter(item => String(item.owner?.id) === String(ownerFilter.value));
  }
  const query = search.value.trim().toLowerCase();
  if (!query) return rows;
  return rows.filter(item =>
    [
      item.request_number,
      item.title,
      item.contact?.name,
      item.order?.order_number,
      item.owner?.name,
    ]
      .filter(Boolean)
      .some(value => value.toLowerCase().includes(query))
  );
});

const kpis = computed(() => [
  ['Pedidos para análise', summary.value.pending || 0],
  ['Documentação', summary.value.documentation || 0],
  ['Em implantação', summary.value.implementation || 0],
  ['Financeiro', summary.value.finance || 0],
  ['Com pendência', summary.value.issues || 0],
  ['SLA crítico', summary.value.overdue || 0],
]);
const criticalAlerts = computed(() => {
  const alerts = [];
  const overdue = requests.value.filter(isOverdue);
  const critical = requests.value.filter(item => item.priority === 'critical' && !['completed','canceled','rejected'].includes(item.status));
  const unassigned = requests.value.filter(item => !item.owner && !['completed','canceled','rejected'].includes(item.status));
  if (overdue.length) alerts.push({label:'SLA vencido',count:overdue.length,tone:'red',icon:'i-lucide-clock-alert'});
  if (critical.length) alerts.push({label:'Prioridade crítica',count:critical.length,tone:'amber',icon:'i-lucide-triangle-alert'});
  if (unassigned.length) alerts.push({label:'Sem responsável',count:unassigned.length,tone:'violet',icon:'i-lucide-user-x'});
  return alerts;
});
const flowStages = computed(() => [
  ['Análise', requests.value.filter(i=>['request','analysis'].includes(i.stage)).length],
  ['Documentação', requests.value.filter(i=>['documentation','contract'].includes(i.stage)).length],
  ['Implantação', requests.value.filter(i=>i.stage==='implementation').length],
  ['Provisionamento', requests.value.filter(i=>i.stage==='provisioning').length],
  ['Financeiro', requests.value.filter(i=>i.stage==='finance').length],
  ['Concluído', requests.value.filter(i=>i.status==='completed').length],
]);
const slaByKind = computed(() => {
  const kinds = [...new Set(requests.value.map(item=>item.request_kind).filter(Boolean))];
  return kinds.map(kind => {
    const scoped=requests.value.filter(item=>item.request_kind===kind);
    const overdue=scoped.filter(isOverdue).length;
    return {kind,total:scoped.length,overdue,onTime:Math.max(0,scoped.length-overdue),rate:scoped.length?Math.round(((scoped.length-overdue)/scoped.length)*100):100};
  });
});
const reportStats = computed(() => ({
  total: requests.value.length,
  completed: requests.value.filter(i=>i.status==='completed').length,
  overdue: requests.value.filter(isOverdue).length,
  critical: requests.value.filter(i=>i.priority==='critical').length,
  averageOpenHours: (() => {
    const open=requests.value.filter(i=>!['completed','canceled','rejected'].includes(i.status));
    if(!open.length) return 0;
    return Math.round(open.reduce((sum,i)=>sum+Math.max(0,(Date.now()-new Date(i.created_at).getTime())/3600000),0)/open.length);
  })(),
}));



const requestStatuses = ['pending', 'in_progress', 'waiting_customer', 'blocked', 'approved', 'rejected', 'canceled', 'completed'];
const priorities = ['low', 'normal', 'high', 'critical'];

const documentRows = computed(() => {
  const rows = [];
  requests.value
    .filter(request =>
      ['documentation', 'contract'].includes(request.stage) ||
      (request.documents || []).length ||
      (request.metadata?.required_documents || []).length
    )
    .forEach(request => {
    const statuses = request.metadata?.document_statuses || {};
    (request.documents || []).forEach(file => {
      rows.push({
        key: `${request.id}-${file.id}`,
        request,
        attachment: file,
        name: file.filename,
        status: file.status || statuses[String(file.id)] || 'received',
        required: false,
      });
    });
    (request.metadata?.required_documents || []).forEach(name => {
      const alreadyAttached = (request.documents || []).some(file =>
        String(file.filename || '').toLowerCase().includes(String(name).toLowerCase())
      );
      if (!alreadyAttached) {
        rows.push({
          key: `${request.id}-required-${name}`,
          request,
          attachment: null,
          name,
          status: statuses[String(name)] || 'pending',
          required: true,
        });
      }
    });
  });
  const query = search.value.trim().toLowerCase();
  return rows.filter(row => {
    const request = row.request;
    return (
      (!query ||
        [row.name, request.request_number, request.contact?.name, request.order?.order_number]
          .filter(Boolean)
          .some(value => String(value).toLowerCase().includes(query))) &&
      (statusFilter.value === 'all' || request.status === statusFilter.value) &&
      (priorityFilter.value === 'all' || request.priority === priorityFilter.value) &&
      (ownerFilter.value === 'all' || String(request.owner?.id) === String(ownerFilter.value))
    );
  });
});

const implementationRows = computed(() =>
  filteredRequests.value.map(request => {
    const checklist =
      request.metadata?.implementation_checklist ||
      request.order?.snapshot?.checklist ||
      [];
    const total = checklist.length;
    const done = checklist.filter(item => Boolean(item.done)).length;
    return { request, checklist, total, done, rate: total ? Math.round((done / total) * 100) : 100 };
  })
);

const provisioningRows = computed(() =>
  filteredRequests.value.map(request => ({
    request,
    completedAt: request.metadata?.provisioning_completed_at,
    mode: request.metadata?.provisioning_completion_mode,
    reference: request.metadata?.provisioning_external_reference,
    required: Boolean(request.metadata?.provisioning_required),
  }))
);

const issueRows = computed(() => {
  const rows = [];
  requests.value.forEach(request => {
    (request.metadata?.issues || []).forEach(issue => rows.push({ request, issue }));
  });
  const query = search.value.trim().toLowerCase();
  return rows.filter(row => {
    if (query && ![row.issue.description, row.request.request_number, row.request.contact?.name].filter(Boolean).some(value => String(value).toLowerCase().includes(query))) return false;
    if (statusFilter.value !== 'all' && row.request.status !== statusFilter.value) return false;
    if (priorityFilter.value !== 'all' && row.request.priority !== priorityFilter.value) return false;
    if (ownerFilter.value !== 'all' && String(row.request.owner?.id) !== String(ownerFilter.value)) return false;
    return true;
  });
});

const activeIssueCount = computed(() =>
  issueRows.value.filter(row => !['resolved', 'canceled'].includes(row.issue.status)).length
);

const processStats = computed(() => ({
  total: filteredRequests.value.length,
  analysis: filteredRequests.value.filter(item => ['request', 'analysis'].includes(item.stage)).length,
  overdue: filteredRequests.value.filter(isOverdue).length,
  value: filteredRequests.value.reduce((sum, item) => sum + Number(item.order?.total_cents || 0), 0),
}));

const documentStats = computed(() => ({
  total: documentRows.value.length,
  pending: documentRows.value.filter(row => ['pending', 'received', 'validating'].includes(row.status)).length,
  approved: documentRows.value.filter(row => row.status === 'approved').length,
  rejected: documentRows.value.filter(row => row.status === 'rejected').length,
}));

const implementationStats = computed(() => ({
  total: implementationRows.value.length,
  completed: implementationRows.value.filter(row => row.rate === 100).length,
  inProgress: implementationRows.value.filter(row => row.rate > 0 && row.rate < 100).length,
  notStarted: implementationRows.value.filter(row => row.rate === 0).length,
}));

const provisioningStats = computed(() => ({
  total: provisioningRows.value.length,
  completed: provisioningRows.value.filter(row => row.completedAt).length,
  manual: provisioningRows.value.filter(row => row.completedAt && row.mode === 'manual').length,
  external: provisioningRows.value.filter(row => row.completedAt && row.mode === 'external').length,
}));

const issueStats = computed(() => ({
  total: issueRows.value.length,
  open: issueRows.value.filter(row => row.issue.status === 'open').length,
  resolved: issueRows.value.filter(row => row.issue.status === 'resolved').length,
  overdue: issueRows.value.filter(row => row.issue.status === 'open' && row.issue.due_at && new Date(row.issue.due_at) < new Date()).length,
}));

const approvalStats = computed(() => ({
  total: filteredRequests.value.length,
  pending: filteredRequests.value.filter(item => ['pending', 'in_progress'].includes(item.status)).length,
  approved: filteredRequests.value.filter(item => item.status === 'approved').length,
  rejected: filteredRequests.value.filter(item => item.status === 'rejected').length,
}));

const changeStats = computed(() => ({
  total: filteredRequests.value.length,
  changes: filteredRequests.value.filter(item => item.request_kind === 'change').length,
  cancellations: filteredRequests.value.filter(item => item.request_kind === 'cancellation').length,
  active: filteredRequests.value.filter(item => !['completed', 'canceled', 'rejected'].includes(item.status)).length,
}));

const mineStats = computed(() => ({
  total: filteredRequests.value.length,
  overdue: filteredRequests.value.filter(isOverdue).length,
  blocked: filteredRequests.value.filter(item => item.status === 'blocked').length,
  critical: filteredRequests.value.filter(item => item.priority === 'critical').length,
}));

const requestStatusLabel = value => ({
  pending: 'Pendente',
  in_progress: 'Em andamento',
  waiting_customer: 'Aguardando cliente',
  blocked: 'Bloqueada',
  approved: 'Aprovada',
  rejected: 'Rejeitada',
  canceled: 'Cancelada',
  completed: 'Concluída',
}[value] || value || '—');

const priorityLabel = value => ({ low: 'Baixa', normal: 'Normal', high: 'Alta', critical: 'Crítica' }[value] || value || '—');

const selectAndUpdate = async (request, attributes) => {
  await openRequest(request);
  await updateRequest(attributes);
};

const selectAndAdvance = async request => {
  await openRequest(request);
  await advance();
};

const tabMeta = computed(() => ({
  mine: ['Minhas tarefas', 'Solicitações atribuídas ao usuário atual.'],
  requests: ['Solicitações', 'Fila completa com status, prioridade e responsável.'],
  process: ['Pedidos para processar', 'Pedidos aprovados que aguardam análise e execução operacional.'],
  docs: ['Documentação', 'Documentos obrigatórios, anexos e validação documental.'],
  implement: ['Implantações', 'Checklist e dependências para implantação real.'],
  provision: ['Provisionamento', 'Confirmação manual ou referência real de integração externa.'],
  issues: ['Pendências', 'Pendências abertas e resolução vinculada à solicitação.'],
  approvals: ['Aprovações', 'Solicitações que exigem decisão do Backoffice.'],
  changes: ['Cancelamentos e alterações', 'Mudanças comerciais com rastreabilidade.'],
}[tab.value] || [tabs.find(item => item[0] === tab.value)?.[1] || 'Backoffice', '']));

const money = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format((Number(value) || 0) / 100);

const formatDate = value =>
  value ? new Date(value).toLocaleString('pt-BR') : 'Sem prazo';

const load = async () => {
  loading.value = true;
  try {
    const [requestResponse, summaryResponse, orderResponse, invoiceResponse, agentResponse] =
      await Promise.all([
        backofficeAPI.list(),
        backofficeAPI.summary(),
        salesOrdersAPI.list(),
        invoicesAPI.list(),
        AgentsAPI.get(),
      ]);
    requests.value = requestResponse.data || [];
    summary.value = summaryResponse.data || {};
    orders.value = orderResponse.data || [];
    invoices.value = invoiceResponse.data || [];
    agents.value = agentResponse.data || [];
    if (selectedInvoice.value) {
      selectedInvoice.value =
        invoices.value.find(item => item.id === selectedInvoice.value.id) ||
        null;
    }
    if (selected.value) {
      selected.value =
        requests.value.find(item => item.id === selected.value.id) || null;
    }
  } catch (error) {
    useAlert(
      error.response?.data?.message || 'Não foi possível carregar o Backoffice.'
    );
  } finally {
    loading.value = false;
  }
};

const goTab = value => {
  tab.value = value;
  selected.value = null;
  router.push({
    name: 'crm_backoffice',
    params: { accountId: route.params.accountId, section: value },
  });
};

const saveRequest = async () => {
  saving.value = true;
  try {
    await backofficeAPI.create({ backoffice_request: { ...form } });
    showForm.value = false;
    Object.assign(form, {
      sales_order_id: '',
      request_kind: 'change',
      priority: 'normal',
      title: '',
      description: '',
      due_at: '',
    });
    await load();
    useAlert('Solicitação criada e vinculada ao pedido.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível criar a solicitação.'
    );
  } finally {
    saving.value = false;
  }
};

const updateRequest = async attributes => {
  if (!selected.value) return;
  saving.value = true;
  try {
    const { data } = await backofficeAPI.update(selected.value.id, {
      backoffice_request: attributes,
    });
    selected.value = data;
    await load();
    useAlert('Solicitação atualizada.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível atualizar a solicitação.'
    );
  } finally {
    saving.value = false;
  }
};

const advance = async () => {
  if (!selected.value) return;
  saving.value = true;
  try {
    const { data } = await backofficeAPI.advance(selected.value.id);
    selected.value = data;
    await load();
    await continueRequest();
    useAlert('Etapa avançada.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível avançar a etapa.'
    );
  } finally {
    saving.value = false;
  }
};

const createInvoice = async () => {
  const order = eligibleInvoiceOrders.value.find(item => String(item.id) === String(invoiceOrderId.value));
  if (!order || !invoiceDueOn.value) return;
  const request = requests.value.find(item => item.order?.id === order.id);
  saving.value = true;
  try {
    const { data } = await invoicesAPI.create({
      invoice: {
        sales_order_id: order.id,
        contract_id: request?.contract?.id,
        status: 'issued',
        issued_on: new Date().toISOString().slice(0, 10),
        due_on: invoiceDueOn.value,
        payment_method: 'boleto',
      },
    });
    selectedInvoice.value = data;
    await load();
    invoiceOrderId.value = '';
    useAlert('Fatura gerada a partir do pedido.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível gerar a fatura.'
    );
  } finally {
    saving.value = false;
  }
};

const registerPayment = async () => {
  if (!selectedInvoice.value || Number(paymentAmount.value) <= 0) return;
  saving.value = true;
  try {
    await paymentsAPI.create({
      payment: {
        invoice_id: selectedInvoice.value.id,
        amount_cents: Math.round(Number(paymentAmount.value) * 100),
        paid_at: new Date().toISOString(),
        method: 'manual',
        reconciliation_status: 'reconciled',
      },
    });
    paymentAmount.value = '';
    await load();
    useAlert('Pagamento registrado e saldo recalculado.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível registrar o pagamento.'
    );
  } finally {
    saving.value = false;
  }
};


const openRequest = async request => {
  try {
    const { data } = await backofficeAPI.show(request.id);
    selected.value = data;
    provisioningMode.value = data.metadata?.provisioning_completion_mode || 'manual';
    provisioningExternalReference.value = data.metadata?.provisioning_external_reference || '';
    provisioningConfirmed.value = false;
  } catch (error) {
    selected.value = request;
    useAlert('Detalhes carregados parcialmente. Não foi possível obter o histórico completo.');
  }
};

const uploadRequestDocuments = async () => {
  if (!selected.value || !documentFiles.value.length) {
    useAlert('Selecione ao menos um documento.');
    return;
  }
  saving.value = true;
  try {
    await backofficeAPI.uploadDocuments(selected.value.id, documentFiles.value);
    documentFiles.value = [];
    await load();
    await openRequest(requests.value.find(item => item.id === selected.value.id) || selected.value);
    useAlert('Documento enviado e persistido.');
  } catch (error) {
    useAlert(error.response?.data?.message || 'Não foi possível enviar o documento.');
  } finally {
    saving.value = false;
  }
};

const setDocumentStatus = async (request, row, nextStatus) => {
  saving.value = true;
  try {
    await backofficeAPI.documentStatus(request.id, {
      document_key: row.attachment?.id || row.name,
      attachment_id: row.attachment?.id,
      status: nextStatus,
    });
    await load();
    if (selected.value?.id === request.id) await openRequest(requests.value.find(item => item.id === request.id) || request);
    useAlert('Status do documento atualizado.');
  } catch (error) {
    useAlert(error.response?.data?.message || 'Não foi possível atualizar o documento.');
  } finally {
    saving.value = false;
  }
};

const downloadRequestDocument = async (request, row) => {
  if (!row.attachment) return;
  try {
    const { data } = await backofficeAPI.downloadDocument(request.id, row.attachment.id);
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = row.attachment.filename || `documento-${row.attachment.id}`;
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    useAlert('Não foi possível baixar o documento.');
  }
};

const toggleImplementationItem = async (index, done) => {
  if (!selected.value) return;
  const metadata = { ...(selected.value.metadata || {}) };
  const source =
    metadata.implementation_checklist ||
    selected.value.order?.snapshot?.checklist ||
    [];
  const checklist = source.map((item, currentIndex) =>
    currentIndex === index ? { ...item, done } : item
  );
  metadata.implementation_checklist = checklist;
  await updateRequest({ metadata });
  await openRequest(requests.value.find(item => item.id === selected.value.id) || selected.value);
};

const createIssue = async () => {
  if (!selected.value || !issueDescription.value.trim()) {
    useAlert('Descreva a pendência.');
    return;
  }
  saving.value = true;
  try {
    const { data } = await backofficeAPI.addIssue(selected.value.id, {
      description: issueDescription.value.trim(),
      issue_type: issueType.value,
      due_at: issueDueAt.value || null,
    });
    selected.value = data;
    issueDescription.value = '';
    issueDueAt.value = '';
    await load();
    useAlert('Pendência registrada.');
  } catch (error) {
    useAlert(error.response?.data?.message || 'Não foi possível registrar a pendência.');
  } finally {
    saving.value = false;
  }
};

const resolveIssue = async (request, issue) => {
  saving.value = true;
  try {
    await backofficeAPI.resolveIssue(request.id, issue.id);
    await load();
    if (selected.value?.id === request.id) await openRequest(requests.value.find(item => item.id === request.id) || request);
    useAlert('Pendência resolvida.');
  } catch (error) {
    useAlert(error.response?.data?.message || 'Não foi possível resolver a pendência.');
  } finally {
    saving.value = false;
  }
};

const confirmProvisioning = async () => {
  if (!selected.value) return;
  if (!provisioningConfirmed.value) {
    useAlert('Confirme que o provisionamento foi realmente executado.');
    return;
  }
  saving.value = true;
  try {
    const { data } = await backofficeAPI.confirmProvisioning(selected.value.id, {
      mode: provisioningMode.value,
      external_reference:
        provisioningMode.value === 'external'
          ? provisioningExternalReference.value.trim()
          : null,
    });
    selected.value = data;
    await load();
    useAlert(
      provisioningMode.value === 'external'
        ? 'Execução externa registrada com referência real.'
        : 'Provisionamento manual confirmado.'
    );
  } catch (error) {
    useAlert(error.response?.data?.message || 'Não foi possível confirmar o provisionamento.');
  } finally {
    saving.value = false;
  }
};

const reopenRequest = async request => {
  saving.value = true;
  try {
    const { data } = await backofficeAPI.reopen(request.id, { stage: 'analysis' });
    await load();
    selected.value = data;
    useAlert('Solicitação reaberta para análise.');
  } catch (error) {
    useAlert(error.response?.data?.message || 'Não foi possível reabrir a solicitação.');
  } finally {
    saving.value = false;
  }
};

const assignOwner = async (request, ownerId) => {
  selected.value = request;
  await updateRequest({ owner_id: ownerId });
};

watch(
  () => route.params.section,
  value => {
    tab.value = validSections.includes(value) ? value : 'overview';
  }
);
onMounted(load);
</script>

<template>
  <div class="h-full overflow-auto bg-slate-50 p-4 sm:p-6">
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <p class="text-xs font-semibold text-emerald-700">CRM / Operações</p>
        <h2 class="text-2xl font-bold">Backoffice</h2>
        <p class="text-sm text-slate-500">
          Fluxo operacional vinculado a pedidos, contratos e clientes do CRM.
        </p>
      </div>
      <div class="flex gap-2">
        <button
          class="rounded-lg border bg-white px-4 py-2 font-semibold"
          :disabled="loading"
          @click="load"
        >
          Atualizar
        </button>
        <button
          class="rounded-lg bg-emerald-600 px-4 py-2 font-semibold text-white"
          @click="showForm = true"
        >
          Nova solicitação
        </button>
      </div>
    </header>

    <div class="mt-4 grid gap-4 xl:grid-cols-[250px_minmax(0,1fr)]">
      <aside class="h-fit rounded-2xl border border-slate-200 bg-white p-3 shadow-sm xl:sticky xl:top-3">
        <div class="mb-3 px-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-emerald-700">Áreas do Backoffice</p>
          <p class="mt-1 text-xs text-slate-500">Navegue pelas filas operacionais.</p>
        </div>
        <nav class="space-y-1">
          <button
            v-for="item in tabs"
            :key="item[0]"
            class="flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-sm font-semibold transition"
            :class="tab === item[0] ? 'bg-emerald-600 text-white shadow-sm' : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'"
            @click="goTab(item[0])"
          >
            <span>{{ item[1] }}</span>
            <i class="i-lucide-chevron-right size-4 opacity-70" />
          </button>
        </nav>
      </aside>
      <main class="min-w-0">

    <section class="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
      <article
        v-for="item in kpis"
        :key="item[0]"
        class="rounded-lg border bg-white p-4"
      >
        <p class="text-xs text-slate-500">{{ item[0] }}</p>
        <strong class="text-2xl">{{ item[1] }}</strong>
      </article>
    </section>

    <section v-if="tab === 'overview'" class="mt-4 grid gap-4 xl:grid-cols-[1.3fr_.7fr]">
      <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <div class="flex items-center justify-between">
          <div><h3 class="font-bold text-slate-900">Fluxo operacional</h3><p class="text-xs text-slate-500">Volume atual por etapa do processo.</p></div>
          <i class="i-lucide-route size-5 text-emerald-600" />
        </div>
        <div class="mt-5 grid gap-3 md:grid-cols-3">
          <div v-for="(item,index) in flowStages" :key="item[0]" class="relative rounded-xl border border-slate-200 bg-slate-50 p-4">
            <span class="text-xs font-semibold text-slate-500">{{index+1}}. {{item[0]}}</span>
            <strong class="mt-2 block text-2xl text-slate-900">{{item[1]}}</strong>
            <span v-if="index<flowStages.length-1" class="absolute -right-3 top-1/2 hidden size-6 -translate-y-1/2 place-content-center rounded-full bg-white text-slate-400 shadow md:grid">→</span>
          </div>
        </div>
      </article>
      <article class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <h3 class="font-bold text-slate-900">Alertas operacionais</h3>
        <div class="mt-4 space-y-3">
          <div v-for="alert in criticalAlerts" :key="alert.label" class="flex items-center justify-between rounded-xl border border-slate-100 bg-slate-50 p-3">
            <div class="flex items-center gap-3"><span class="grid size-9 place-content-center rounded-lg bg-amber-50 text-amber-600"><i :class="alert.icon" class="size-4"/></span><span class="text-sm font-semibold text-slate-700">{{alert.label}}</span></div>
            <strong class="text-lg text-slate-900">{{alert.count}}</strong>
          </div>
          <p v-if="!criticalAlerts.length" class="rounded-xl bg-emerald-50 p-4 text-sm font-semibold text-emerald-700">Nenhum alerta crítico no momento.</p>
        </div>
      </article>
    </section>

    <section v-if="tab === 'sla'" class="mt-4 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div class="mb-4"><h3 class="font-bold text-slate-900">SLA por tipo de solicitação</h3><p class="text-sm text-slate-500">Cumprimento de prazo e ocorrências vencidas.</p></div>
      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <div v-for="item in slaByKind" :key="item.kind" class="rounded-xl border border-slate-200 p-4">
          <div class="flex justify-between"><span class="text-sm font-semibold capitalize">{{item.kind}}</span><b :class="item.rate>=90?'text-emerald-600':item.rate>=70?'text-amber-600':'text-red-600'">{{item.rate}}%</b></div>
          <div class="mt-3 h-2 rounded-full bg-slate-100"><div class="h-full rounded-full bg-emerald-500" :style="{width:`${item.rate}%`}"/></div>
          <div class="mt-3 flex justify-between text-xs text-slate-500"><span>{{item.onTime}} no prazo</span><span>{{item.overdue}} vencidas</span></div>
        </div>
      </div>
    </section>

    <section v-if="tab === 'reports'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-2xl border bg-white p-5 shadow-sm"><p class="text-xs text-slate-500">Solicitações</p><strong class="mt-1 block text-2xl">{{reportStats.total}}</strong></article>
        <article class="rounded-2xl border bg-white p-5 shadow-sm"><p class="text-xs text-slate-500">Concluídas</p><strong class="mt-1 block text-2xl text-emerald-600">{{reportStats.completed}}</strong></article>
        <article class="rounded-2xl border bg-white p-5 shadow-sm"><p class="text-xs text-slate-500">SLA vencido</p><strong class="mt-1 block text-2xl text-red-600">{{reportStats.overdue}}</strong></article>
        <article class="rounded-2xl border bg-white p-5 shadow-sm"><p class="text-xs text-slate-500">Tempo médio em aberto</p><strong class="mt-1 block text-2xl text-blue-600">{{reportStats.averageOpenHours}}h</strong></article>
      </div>
      <article class="rounded-2xl border bg-white p-5 shadow-sm">
        <h3 class="font-bold">Relatório por etapa</h3>
        <div class="mt-4 grid gap-3 md:grid-cols-3">
          <div v-for="item in flowStages" :key="item[0]" class="rounded-xl bg-slate-50 p-4"><span class="text-xs text-slate-500">{{item[0]}}</span><strong class="block text-xl">{{item[1]}}</strong></div>
        </div>
      </article>
      <article class="rounded-2xl border bg-white p-5 shadow-sm">
        <h3 class="font-bold">SLA consolidado</h3>
        <div class="mt-4 overflow-x-auto"><table class="w-full min-w-[650px] text-sm"><thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Tipo</th><th>Total</th><th>No prazo</th><th>Vencidas</th><th>Cumprimento</th></tr></thead><tbody><tr v-for="item in slaByKind" :key="item.kind" class="border-b"><td class="p-3 font-semibold capitalize">{{item.kind}}</td><td>{{item.total}}</td><td>{{item.onTime}}</td><td>{{item.overdue}}</td><td><b>{{item.rate}}%</b></td></tr></tbody></table></div>
      </article>
    </section>

    <section
      v-if="tab === 'finance'"
      class="mt-4 grid gap-4 xl:grid-cols-[minmax(0,1fr)_340px]"
    >
      <div class="rounded-lg border bg-white p-4">
        <form class="mb-4 grid gap-3 rounded-xl border p-4 sm:grid-cols-2" @submit.prevent="createInvoice">
          <h3 class="font-bold sm:col-span-2">{{ t('CRM.WORKFLOW_UI.FIRST_INVOICE') }}</h3>
          <label class="text-sm">{{ t('CRM.WORKFLOW_UI.ELIGIBLE_ORDER') }}<select v-model="invoiceOrderId" required class="mt-1 w-full rounded-lg border p-2"><option value="">{{ t('CRM.WORKFLOW_UI.CHOOSE_ORDER') }}</option><option v-for="order in eligibleInvoiceOrders" :key="order.id" :value="order.id">{{ order.order_number }} — {{ order.contact?.name || order.snapshot?.customer_name }} — {{ money(order.total_cents) }}</option></select></label>
          <label class="text-sm">{{ t('CRM.WORKFLOW_UI.DUE_DATE') }}<input v-model="invoiceDueOn" required type="date" class="mt-1 w-full rounded-lg border p-2" /></label>
          <p v-if="!eligibleInvoiceOrders.length" class="text-sm text-slate-600 sm:col-span-2">{{ t('CRM.WORKFLOW_UI.NO_ELIGIBLE_ORDERS') }}</p>
          <button class="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white sm:col-span-2" :disabled="saving || !invoiceOrderId">{{ t('CRM.WORKFLOW_UI.CREATE_INVOICE') }}</button>
        </form>
        <div class="mb-4 rounded-xl border p-4"><label class="block text-sm">{{ t('CRM.WORKFLOW_UI.FINANCE_REQUEST') }}<select class="mt-1 w-full rounded-lg border p-2" :value="selected?.stage === 'finance' ? selected.id : ''" @change="selectRequest"><option value="">{{ t('CRM.WORKFLOW_UI.CHOOSE_REQUEST') }}</option><option v-for="request in selectableRequests.filter(item => item.stage === 'finance')" :key="request.id" :value="request.id">{{ request.request_number }} — {{ request.order?.order_number }}</option></select></label><button v-if="selected?.stage === 'finance'" class="mt-3 rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white" :disabled="saving" @click="advance">{{ t('CRM.WORKFLOW_UI.ADVANCE_FINANCE') }}</button><p class="mt-2 text-xs text-slate-600">{{ t('CRM.WORKFLOW_UI.PAYMENT_NOTE') }}</p></div>
        <h3 class="font-bold">Faturas do CRM</h3>
        <p v-if="!invoices.length" class="py-8 text-center text-slate-500">
          Nenhuma fatura gerada.
        </p>
        <div v-else class="mt-3 overflow-x-auto">
          <table class="w-full min-w-[700px] text-sm">
            <thead>
              <tr class="border-b text-left text-xs uppercase text-slate-500">
                <th class="p-2">Fatura</th>
                <th>Pedido</th>
                <th>Cliente</th>
                <th>{{ t('CRM.WORKFLOW_UI.DUE_DATE') }}</th>
                <th>Total</th>
                <th>Saldo</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="invoice in invoices"
                :key="invoice.id"
                class="cursor-pointer border-b hover:bg-slate-50"
                @click="selectedInvoice = invoice"
              >
                <td class="p-3 font-semibold text-blue-700">
                  {{ invoice.invoice_number }}
                </td>
                <td>{{ invoice.order?.order_number }}</td>
                <td>{{ invoice.contact?.name || 'Sem contato' }}</td>
                <td>{{ invoice.due_on }}</td>
                <td>{{ money(invoice.total_cents) }}</td>
                <td>{{ money(invoice.balance_cents) }}</td>
                <td>{{ invoice.status }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
      <aside class="rounded-lg border bg-white p-4">
        <template v-if="selectedInvoice">
          <h3 class="font-bold">{{ selectedInvoice.invoice_number }}</h3>
          <p class="mt-2 text-sm text-slate-500">
            Saldo: {{ money(selectedInvoice.balance_cents) }}
          </p>
          <div
            v-for="payment in selectedInvoice.payments"
            :key="payment.id"
            class="mt-3 flex justify-between border-b pb-2 text-sm"
          >
            <span>{{ formatDate(payment.paid_at) }}</span>
            <b>{{ money(payment.amount_cents) }}</b>
          </div>
          <form
            v-if="selectedInvoice.balance_cents > 0"
            class="mt-4"
            @submit.prevent="registerPayment"
          >
            <label class="text-sm">
              Valor recebido (R$)
              <input
                v-model="paymentAmount"
                required
                type="number"
                min="0.01"
                step="0.01"
                class="mt-1 w-full rounded-lg border p-2"
              />
            </label>
            <button
              class="mt-3 w-full rounded-lg bg-emerald-600 p-2 font-semibold text-white"
              :disabled="saving"
            >
              Registrar pagamento
            </button>
          </form>
        </template>
        <p v-else class="text-sm text-slate-500">
          Selecione uma fatura para consultar pagamentos e registrar
          recebimento.
        </p>
      </aside>
    </section>

    <section
      v-if="['mine','requests','process','docs','contracts','implement','provision','issues','approvals','changes'].includes(tab)"
      class="mt-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm"
    >
      <div class="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-emerald-700">{{ tabMeta[0] }}</p>
          <p class="mt-1 text-sm text-slate-500">{{ tabMeta[1] }}</p>
        </div>
        <div class="flex flex-wrap gap-2">
          <input v-model="search" class="min-w-[220px] rounded-lg border px-3 py-2 text-sm" placeholder="Buscar nesta área" />
          <select v-model="statusFilter" class="rounded-lg border px-3 py-2 text-sm">
            <option value="all">Todos os status</option>
            <option v-for="value in requestStatuses" :key="value" :value="value">{{ requestStatusLabel(value) }}</option>
          </select>
          <select v-model="priorityFilter" class="rounded-lg border px-3 py-2 text-sm">
            <option value="all">Todas as prioridades</option>
            <option v-for="value in priorities" :key="value" :value="value">{{ priorityLabel(value) }}</option>
          </select>
          <select v-model="ownerFilter" class="rounded-lg border px-3 py-2 text-sm">
            <option value="all">Todos os responsáveis</option>
            <option v-for="agent in agents" :key="agent.id" :value="String(agent.id)">{{ agent.name }}</option>
          </select>
        </div>
      </div>
    </section>

    <!-- Minhas tarefas: cartões orientados a ação, não uma cópia da fila geral. -->
    <section v-if="tab === 'mine'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Minhas tarefas</p><strong class="text-2xl">{{ mineStats.total }}</strong></article>
        <article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">SLA vencido</p><strong class="text-2xl text-red-600">{{ mineStats.overdue }}</strong></article>
        <article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Bloqueadas</p><strong class="text-2xl text-amber-600">{{ mineStats.blocked }}</strong></article>
        <article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Prioridade crítica</p><strong class="text-2xl text-violet-600">{{ mineStats.critical }}</strong></article>
      </div>
      <div class="grid gap-3 lg:grid-cols-2">
        <button v-for="item in filteredRequests" :key="item.id" type="button" class="rounded-2xl border bg-white p-4 text-left shadow-sm transition hover:border-emerald-300" @click="openRequest(item)">
          <div class="flex items-start justify-between gap-3"><div><p class="text-xs font-semibold text-emerald-700">{{ item.request_number }}</p><h3 class="mt-1 font-bold">{{ item.title }}</h3></div><span class="rounded-full bg-slate-100 px-2 py-1 text-xs">{{ priorityLabel(item.priority) }}</span></div>
          <div class="mt-4 grid grid-cols-2 gap-2 text-sm"><p><span class="text-slate-500">Cliente</span><b class="block">{{ item.contact?.name || 'Sem contato' }}</b></p><p><span class="text-slate-500">Etapa</span><b class="block">{{ item.stage }}</b></p><p><span class="text-slate-500">Status</span><b class="block">{{ requestStatusLabel(item.status) }}</b></p><p><span class="text-slate-500">Prazo</span><b class="block" :class="{'text-red-600':isOverdue(item)}">{{ formatDate(item.due_at) }}</b></p></div>
        </button>
        <p v-if="!filteredRequests.length" class="rounded-2xl border bg-white p-8 text-center text-sm text-slate-500 lg:col-span-2">Nenhuma tarefa atribuída a você com os filtros atuais.</p>
      </div>
    </section>

    <!-- Solicitações: fila administrativa completa. -->
    <section v-if="tab === 'requests'" class="mt-4 grid gap-4 xl:grid-cols-[minmax(0,1fr)_340px]">
      <article class="rounded-2xl border bg-white p-4 shadow-sm">
        <div class="overflow-x-auto">
          <table class="w-full min-w-[920px] text-sm">
            <thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Solicitação</th><th>Cliente</th><th>Tipo</th><th>Entrada</th><th>Status</th><th>Prioridade</th><th>Responsável</th><th>Prazo</th></tr></thead>
            <tbody><tr v-for="item in filteredRequests" :key="item.id" class="cursor-pointer border-b hover:bg-slate-50" @click="openRequest(item)"><td class="p-3 font-semibold text-blue-700">{{ item.request_number }}</td><td>{{ item.contact?.name || 'Sem contato' }}</td><td>{{ item.request_kind }}</td><td>{{ formatDate(item.created_at) }}</td><td>{{ requestStatusLabel(item.status) }}</td><td>{{ priorityLabel(item.priority) }}</td><td>{{ item.owner?.name || 'Sem responsável' }}</td><td :class="{'font-semibold text-red-600':isOverdue(item)}">{{ formatDate(item.due_at) }}</td></tr></tbody>
          </table>
          <p v-if="!filteredRequests.length" class="py-10 text-center text-slate-500">Nenhuma solicitação encontrada.</p>
        </div>
      </article>
      <aside class="h-fit rounded-2xl border bg-white p-4 shadow-sm xl:sticky xl:top-3">
        <template v-if="selected"><p class="text-xs font-semibold text-blue-700">{{ selected.request_number }}</p><h3 class="mt-1 font-bold">{{ selected.title }}</h3><button class="mt-3 w-full rounded-lg bg-blue-600 p-2 font-semibold text-white" @click="continueRequest">{{ t('CRM.WORKFLOW_UI.CONTINUE_STAGE') }}</button><p class="mt-3 text-sm text-slate-600">{{ selected.description || 'Sem observações.' }}</p><dl class="mt-4 space-y-2 text-sm"><div><dt class="text-slate-500">Pedido</dt><dd class="font-semibold">{{ selected.order?.order_number }}</dd></div><div><dt class="text-slate-500">Cliente</dt><dd>{{ selected.contact?.name || 'Sem contato' }}</dd></div><div><dt class="text-slate-500">Fluxo</dt><dd>{{ selected.stage }} · {{ requestStatusLabel(selected.status) }}</dd></div><div><dt class="text-slate-500">Responsável</dt><dd>{{ selected.owner?.name || 'Sem responsável' }}</dd></div></dl><select class="mt-4 w-full rounded-lg border p-2 text-sm" :value="selected.owner?.id || ''" @change="assignOwner(selected,$event.target.value)"><option disabled value="">Atribuir responsável</option><option v-for="agent in agents" :key="agent.id" :value="agent.id">{{agent.name}}</option></select></template>
        <p v-else class="text-sm text-slate-500">Selecione uma solicitação para visualizar os detalhes.</p>
      </aside>
    </section>

    <!-- Pedidos para processar: visão centrada no pedido e nas dependências. -->
    <section v-if="tab === 'process'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Na fila</p><strong class="text-2xl">{{processStats.total}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Em análise</p><strong class="text-2xl text-blue-600">{{processStats.analysis}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">SLA vencido</p><strong class="text-2xl text-red-600">{{processStats.overdue}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Valor em análise</p><strong class="text-xl text-emerald-700">{{money(processStats.value)}}</strong></article></div>
      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_360px]">
        <article class="rounded-2xl border bg-white p-4 shadow-sm"><div class="overflow-x-auto"><table class="w-full min-w-[900px] text-sm"><thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Pedido</th><th>Cliente</th><th>Valor</th><th>MRR</th><th>Status CRM</th><th>Etapa</th><th>Prioridade</th><th>Responsável</th></tr></thead><tbody><tr v-for="item in filteredRequests" :key="item.id" class="cursor-pointer border-b hover:bg-slate-50" @click="openRequest(item)"><td class="p-3 font-semibold text-blue-700">{{item.order?.order_number}}</td><td>{{item.contact?.name||'Sem contato'}}</td><td>{{money(item.order?.total_cents)}}</td><td>{{money(item.order?.monthly_cents)}}</td><td>{{item.order?.status}}</td><td>{{item.stage}}</td><td>{{priorityLabel(item.priority)}}</td><td>{{item.owner?.name||'Sem responsável'}}</td></tr></tbody></table><p v-if="!filteredRequests.length" class="py-10 text-center text-slate-500">Nenhum pedido aguardando processamento.</p></div></article>
        <aside class="h-fit rounded-2xl border bg-white p-4 shadow-sm xl:sticky xl:top-3"><template v-if="selected"><p class="text-xs font-semibold text-blue-700">{{selected.order?.order_number}}</p><h3 class="text-lg font-bold">{{selected.contact?.name||'Sem contato'}}</h3><div class="mt-4 grid grid-cols-2 gap-3 text-sm"><div class="rounded-xl bg-slate-50 p-3"><span class="text-xs text-slate-500">Valor</span><b class="block">{{money(selected.order?.total_cents)}}</b></div><div class="rounded-xl bg-slate-50 p-3"><span class="text-xs text-slate-500">MRR</span><b class="block">{{money(selected.order?.monthly_cents)}}</b></div></div><p class="mt-4 text-sm"><span class="text-slate-500">Próxima etapa:</span> <b>{{selected.next_stage||'Concluir'}}</b></p><button class="mt-4 w-full rounded-lg bg-emerald-600 p-2 font-semibold text-white" :disabled="saving||selected.status==='completed'" @click="advance">Avançar conforme dependências</button><button class="mt-2 w-full rounded-lg border p-2 text-sm" :disabled="saving" @click="updateRequest({status:'blocked'})">Bloquear para revisão</button></template><p v-else class="text-sm text-slate-500">Selecione um pedido para analisar valor, etapa e dependências reais.</p></aside>
      </div>
    </section>

    <!-- Documentação: visão por documento, com persistência, download e validação. -->
    <section v-if="tab === 'contracts'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-3">
        <article v-for="state in ['total','signed','pending']" :key="state" class="rounded-xl border border-n-weak bg-n-solid-2 p-4"><p class="text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.CONTRACT_QUEUE.' + state) }}</p><strong class="mt-2 block text-2xl">{{ state === 'total' ? filteredRequests.length : filteredRequests.filter(item => (item.contract?.signature_status === 'signed') === (state === 'signed')).length }}</strong></article>
      </div>
      <article class="rounded-xl border border-n-weak bg-n-solid-2 p-4">
        <p class="mb-4 text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.CONTRACT_QUEUE_HELP') }}</p>
        <div class="overflow-x-auto"><table class="w-full min-w-[650px] text-sm"><thead class="bg-n-slate-2 text-left text-n-slate-11"><tr><th class="p-3">{{ t('CRM.HOMOLOGATION.REQUEST') }}</th><th>{{ t('CRM.HOMOLOGATION.CONTRACTS') }}</th><th>{{ t('CRM.HOMOLOGATION.SIGNATURE') }}</th><th>{{ t('CRM.HOMOLOGATION.ACTIONS') }}</th></tr></thead><tbody><tr v-for="item in filteredRequests" :key="item.id" class="border-t border-n-weak"><td class="p-3"><strong>{{ item.request_number }}</strong><p class="text-xs text-n-slate-11">{{ item.contact?.name }} · {{ item.order?.order_number }}</p></td><td>{{ item.contract?.contract_number || t('CRM.HOMOLOGATION.NO_CONTRACT') }}</td><td>{{ item.contract?.signature_status || '—' }}</td><td><div class="flex flex-wrap gap-2"><RouterLink v-if="item.contract" :to="{name:'crm_contracts',query:{contractId:item.contract.id}}" class="rounded-lg border border-blue-300 px-3 py-2 text-blue-700">{{ t('CRM.WORKFLOW_UI.OPEN_CONTRACT') }}</RouterLink><RouterLink v-else :to="{name:'crm_contract_new',query:{orderId:item.order?.id}}" class="rounded-lg border px-3 py-2">{{ t('CRM.HOMOLOGATION.CREATE_CONTRACT') }}</RouterLink><button :disabled="saving" class="rounded-lg bg-blue-600 px-3 py-2 text-white" @click="selectAndAdvance(item)">{{ t('CRM.HOMOLOGATION.VALIDATE_SIGNATURE') }}</button></div></td></tr></tbody></table></div>
        <p v-if="!filteredRequests.length" class="py-8 text-center text-sm text-n-slate-11">{{ t('CRM.HOMOLOGATION.EMPTY_CONTRACT_QUEUE') }}</p>
      </article>
    </section>

    <section v-if="tab === 'docs'" class="mt-4 space-y-4">
      <label class="block rounded-xl border bg-white p-4 text-sm">{{ t('CRM.WORKFLOW_UI.DOCUMENT_REQUEST') }}<select class="mt-2 w-full rounded-lg border p-2" :value="selected?.id || ''" @change="selectRequest"><option value="">{{ t('CRM.WORKFLOW_UI.CHOOSE_DOCUMENT_REQUEST') }}</option><option v-for="request in documentRequests" :key="request.id" :value="request.id">{{ request.request_number }} — {{ request.contact?.name || 'Sem contato' }} — {{ request.stage }}</option></select></label>
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Documentos</p><strong class="text-2xl">{{documentStats.total}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Em validação</p><strong class="text-2xl text-amber-600">{{documentStats.pending}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Aprovados</p><strong class="text-2xl text-emerald-600">{{documentStats.approved}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Rejeitados</p><strong class="text-2xl text-red-600">{{documentStats.rejected}}</strong></article></div>
      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_360px]">
        <article class="rounded-2xl border bg-white p-4 shadow-sm"><div class="overflow-x-auto"><table class="w-full min-w-[880px] text-sm"><thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Documento</th><th>Solicitação</th><th>Cliente</th><th>Status</th><th>Obrigatório</th><th>Ações</th></tr></thead><tbody><tr v-for="row in documentRows" :key="row.key" class="border-b"><td class="p-3 font-semibold">{{row.name}}</td><td><button class="text-blue-700" @click="openRequest(row.request)">{{row.request.request_number}}</button></td><td>{{row.request.contact?.name||'Sem contato'}}</td><td>{{row.status}}</td><td>{{row.required?'Sim':'Não'}}</td><td><div class="flex flex-wrap gap-1"><button v-if="row.attachment" class="rounded border px-2 py-1" @click="downloadRequestDocument(row.request,row)">Baixar</button><button class="rounded border border-emerald-300 px-2 py-1 text-emerald-700" :disabled="saving" @click="setDocumentStatus(row.request,row,'approved')">Aprovar</button><button class="rounded border border-red-300 px-2 py-1 text-red-700" :disabled="saving" @click="setDocumentStatus(row.request,row,'rejected')">Rejeitar</button></div></td></tr></tbody></table><p v-if="!documentRows.length" class="py-10 text-center text-slate-500">Nenhum documento nesta fila.</p></div></article>
        <aside class="h-fit rounded-2xl border bg-white p-4 shadow-sm xl:sticky xl:top-3"><template v-if="selected"><p class="text-xs font-semibold text-violet-700">{{selected.request_number}}</p><h3 class="font-bold">Documentos da solicitação</h3><p class="mt-1 text-sm text-slate-500">{{selected.contact?.name||'Sem contato'}}</p><label class="mt-4 block rounded-xl border border-dashed p-4 text-center text-sm text-slate-500">Selecionar documentos<input type="file" multiple class="mt-2 block w-full text-xs" @change="documentFiles=Array.from($event.target.files||[])" /></label><button class="mt-3 w-full rounded-lg bg-violet-600 p-2 font-semibold text-white disabled:opacity-50" :disabled="saving||!documentFiles.length" @click="uploadRequestDocuments">Enviar e persistir</button><p class="mt-4 text-xs text-slate-500">A fila só avança quando os documentos obrigatórios estiverem aprovados.</p><div v-if="selected.stage === 'contract'" class="mt-4 rounded-lg border p-3 text-sm"><p>Contrato: {{selected.contract?.contract_number || 'Não vinculado'}}</p><p>Assinatura: {{selected.contract?.signature_status || 'Pendente'}}</p><button v-if="selected.contract" class="mt-2 rounded border border-blue-300 px-3 py-2 text-blue-700" @click="openContract">{{ t('CRM.WORKFLOW_UI.OPEN_CONTRACT') }}</button></div><button v-if="['documentation','contract'].includes(selected.stage)" class="mt-4 w-full rounded-lg bg-blue-600 p-2 font-semibold text-white" :disabled="saving" @click="advance">{{ t('CRM.WORKFLOW_UI.ADVANCE_DOCUMENTS') }}</button></template><p v-else class="text-sm text-slate-500">Clique no número de uma solicitação para anexar documentos.</p></aside>
      </div>
    </section>

    <!-- Implantações: progresso e checklist próprios. -->
    <section v-if="tab === 'implement'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Implantações</p><strong class="text-2xl">{{implementationStats.total}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Concluídas no checklist</p><strong class="text-2xl text-emerald-600">{{implementationStats.completed}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Em execução</p><strong class="text-2xl text-blue-600">{{implementationStats.inProgress}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Não iniciadas</p><strong class="text-2xl text-slate-600">{{implementationStats.notStarted}}</strong></article></div>
      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_380px]">
        <div class="grid gap-3 lg:grid-cols-2"><button v-for="row in implementationRows" :key="row.request.id" class="rounded-2xl border bg-white p-4 text-left shadow-sm hover:border-blue-300" @click="openRequest(row.request)"><div class="flex justify-between gap-3"><div><p class="text-xs font-semibold text-blue-700">{{row.request.request_number}}</p><h3 class="font-bold">{{row.request.contact?.name||'Sem contato'}}</h3></div><b>{{row.rate}}%</b></div><div class="mt-3 h-2 overflow-hidden rounded-full bg-slate-100"><div class="h-full rounded-full bg-blue-500" :style="{width:`${row.rate}%`}" /></div><div class="mt-3 flex justify-between text-xs text-slate-500"><span>{{row.done}} de {{row.total}} itens</span><span>{{formatDate(row.request.due_at)}}</span></div></button><p v-if="!implementationRows.length" class="rounded-2xl border bg-white p-8 text-center text-slate-500 lg:col-span-2">Nenhuma implantação nesta fila.</p></div>
        <aside class="h-fit rounded-2xl border bg-white p-4 shadow-sm xl:sticky xl:top-3"><template v-if="selected"><p class="text-xs font-semibold text-blue-700">{{selected.request_number}}</p><h3 class="font-bold">Checklist de implantação</h3><div class="mt-4 space-y-2"><label v-for="(item,index) in (selected.metadata?.implementation_checklist||selected.order?.snapshot?.checklist||[])" :key="`${index}-${item.label}`" class="flex items-start gap-2 rounded-lg border p-3 text-sm"><input type="checkbox" class="mt-0.5" :checked="!!item.done" :disabled="saving" @change="toggleImplementationItem(index,$event.target.checked)" /><span><b class="block">{{item.label||item.name||`Etapa ${index+1}`}}</b><span v-if="item.description" class="text-xs text-slate-500">{{item.description}}</span></span></label><p v-if="!(selected.metadata?.implementation_checklist||selected.order?.snapshot?.checklist||[]).length" class="rounded-lg bg-amber-50 p-3 text-sm text-amber-800">Este pedido não possui checklist operacional configurado.</p></div><button class="mt-4 w-full rounded-lg bg-blue-600 p-2 font-semibold text-white" :disabled="saving||selected.status==='completed'" @click="advance">Validar dependências e avançar</button></template><p v-else class="text-sm text-slate-500">Selecione uma implantação para acompanhar o checklist.</p></aside>
      </div>
    </section>

    <!-- Provisionamento: confirmação explícita; externo exige referência real. -->
    <section v-if="tab === 'provision'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Na fila</p><strong class="text-2xl">{{provisioningStats.total}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Executados</p><strong class="text-2xl text-emerald-600">{{provisioningStats.completed}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Manual</p><strong class="text-2xl">{{provisioningStats.manual}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Integração externa</p><strong class="text-2xl text-indigo-600">{{provisioningStats.external}}</strong></article></div>
      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_380px]">
        <article class="rounded-2xl border bg-white p-4 shadow-sm"><div class="overflow-x-auto"><table class="w-full min-w-[820px] text-sm"><thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Solicitação</th><th>Pedido</th><th>Cliente</th><th>Execução</th><th>Modo</th><th>Referência</th><th>Responsável</th></tr></thead><tbody><tr v-for="row in provisioningRows" :key="row.request.id" class="cursor-pointer border-b hover:bg-slate-50" @click="openRequest(row.request)"><td class="p-3 font-semibold text-indigo-700">{{row.request.request_number}}</td><td>{{row.request.order?.order_number}}</td><td>{{row.request.contact?.name||'Sem contato'}}</td><td>{{row.completedAt?formatDate(row.completedAt):'Pendente'}}</td><td>{{row.mode||'—'}}</td><td>{{row.reference||'—'}}</td><td>{{row.request.owner?.name||'Sem responsável'}}</td></tr></tbody></table><p v-if="!provisioningRows.length" class="py-10 text-center text-slate-500">Nenhum provisionamento nesta fila.</p></div></article>
        <aside class="h-fit rounded-2xl border bg-white p-4 shadow-sm xl:sticky xl:top-3"><template v-if="selected"><p class="text-xs font-semibold text-indigo-700">{{selected.request_number}}</p><h3 class="font-bold">Confirmar execução</h3><p v-if="selected.metadata?.provisioning_completed_at" class="mt-3 rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">Executado em {{formatDate(selected.metadata.provisioning_completed_at)}} via {{selected.metadata.provisioning_completion_mode}}.</p><template v-else><label class="mt-4 block text-sm">Modo<select v-model="provisioningMode" class="mt-1 w-full rounded-lg border p-2"><option value="manual">Manual</option><option value="external">Integração externa</option></select></label><label v-if="provisioningMode==='external'" class="mt-3 block text-sm">Referência retornada pela integração<input v-model="provisioningExternalReference" class="mt-1 w-full rounded-lg border p-2" placeholder="ID real da execução externa" /></label><label class="mt-4 flex gap-2 rounded-lg bg-amber-50 p-3 text-sm text-amber-900"><input v-model="provisioningConfirmed" type="checkbox" /> Confirmo que o provisionamento foi realmente executado.</label><button class="mt-3 w-full rounded-lg bg-indigo-600 p-2 font-semibold text-white" :disabled="saving" @click="confirmProvisioning">Registrar execução</button><p class="mt-2 text-xs text-slate-500">Selecionar “externa” não executa integração; é obrigatório informar uma referência real retornada pelo sistema externo.</p></template><button class="mt-4 w-full rounded-lg bg-blue-600 p-2 font-semibold text-white" :disabled="saving||selected.status==='completed'" @click="advance">{{ t('CRM.WORKFLOW_UI.ADVANCE_PROVISIONING') }}</button></template><p v-else class="text-sm text-slate-500">Selecione uma solicitação para registrar a execução.</p></aside>
      </div>
    </section>

    <!-- Pendências: itens próprios com resolução individual. -->
    <section v-if="tab === 'issues'" class="mt-4 space-y-4">
      <label class="block rounded-xl border bg-white p-4 text-sm">{{ t('CRM.WORKFLOW_UI.ISSUE_REQUEST') }}<select class="mt-2 w-full rounded-lg border p-2" :value="selected?.id || ''" @change="selectRequest"><option value="">{{ t('CRM.WORKFLOW_UI.CHOOSE_REQUEST') }}</option><option v-for="request in selectableRequests" :key="request.id" :value="request.id">{{ request.request_number }} — {{ request.contact?.name || 'Sem contato' }} — {{ request.title }}</option></select></label>
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Pendências</p><strong class="text-2xl">{{issueStats.total}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Abertas</p><strong class="text-2xl text-amber-600">{{issueStats.open}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Vencidas</p><strong class="text-2xl text-red-600">{{issueStats.overdue}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Resolvidas</p><strong class="text-2xl text-emerald-600">{{issueStats.resolved}}</strong></article></div>
      <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_380px]">
        <article class="rounded-2xl border bg-white p-4 shadow-sm"><div class="overflow-x-auto"><table class="w-full min-w-[850px] text-sm"><thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Pendência</th><th>Solicitação</th><th>Cliente</th><th>Tipo</th><th>Status</th><th>Prazo</th><th>Ação</th></tr></thead><tbody><tr v-for="row in issueRows" :key="row.issue.id" class="border-b"><td class="max-w-[300px] p-3">{{row.issue.description}}</td><td><button class="font-semibold text-blue-700" @click="openRequest(row.request)">{{row.request.request_number}}</button></td><td>{{row.request.contact?.name||'Sem contato'}}</td><td>{{row.issue.type}}</td><td>{{row.issue.status}}</td><td>{{formatDate(row.issue.due_at)}}</td><td><button v-if="row.issue.status==='open'" class="rounded border border-emerald-300 px-2 py-1 text-emerald-700" :disabled="saving" @click="resolveIssue(row.request,row.issue)">Resolver</button><span v-else class="text-xs text-slate-500">{{formatDate(row.issue.resolved_at)}}</span></td></tr></tbody></table><p v-if="!issueRows.length" class="py-10 text-center text-slate-500">Nenhuma pendência registrada.</p></div></article>
        <aside class="h-fit rounded-2xl border bg-white p-4 shadow-sm xl:sticky xl:top-3"><template v-if="selected"><p class="text-xs font-semibold text-amber-700">{{selected.request_number}}</p><h3 class="font-bold">Nova pendência</h3><label class="mt-4 block text-sm">Tipo<select v-model="issueType" class="mt-1 w-full rounded-lg border p-2"><option value="operational">Operacional</option><option value="customer">Cliente</option><option value="commercial">Comercial</option><option value="technical">Técnica</option><option value="financial">Financeira</option></select></label><label class="mt-3 block text-sm">Prazo<input v-model="issueDueAt" type="datetime-local" class="mt-1 w-full rounded-lg border p-2" /></label><label class="mt-3 block text-sm">Descrição<textarea v-model="issueDescription" rows="4" class="mt-1 w-full rounded-lg border p-2" /></label><button class="mt-3 w-full rounded-lg bg-amber-600 p-2 font-semibold text-white" :disabled="saving" @click="createIssue">Registrar pendência</button><button v-if="selected.stage === 'issues'" class="mt-3 w-full rounded-lg border border-blue-300 p-2 text-blue-700" :disabled="saving" @click="advance">{{ t('CRM.WORKFLOW_UI.ADVANCE_ISSUES') }}</button></template><p v-else class="text-sm text-slate-500">{{ t('CRM.WORKFLOW_UI.FIRST_ISSUE_NOTE') }}</p></aside>
      </div>
    </section>

    <!-- Aprovações: decisões explícitas e separadas da fila genérica. -->
    <section v-if="tab === 'approvals'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Aprovações</p><strong class="text-2xl">{{approvalStats.total}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Pendentes</p><strong class="text-2xl text-amber-600">{{approvalStats.pending}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Aprovadas</p><strong class="text-2xl text-emerald-600">{{approvalStats.approved}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Rejeitadas</p><strong class="text-2xl text-red-600">{{approvalStats.rejected}}</strong></article></div>
      <div class="grid gap-3 lg:grid-cols-2"><article v-for="item in filteredRequests" :key="item.id" class="rounded-2xl border bg-white p-5 shadow-sm"><div class="flex justify-between gap-3"><div><p class="text-xs font-semibold text-violet-700">{{item.request_number}}</p><h3 class="font-bold">{{item.title}}</h3><p class="mt-1 text-sm text-slate-500">{{item.contact?.name||'Sem contato'}} · {{item.order?.order_number}}</p></div><span class="h-fit rounded-full bg-slate-100 px-2 py-1 text-xs">{{requestStatusLabel(item.status)}}</span></div><p class="mt-4 text-sm text-slate-600">{{item.description||'Sem justificativa adicional.'}}</p><div class="mt-4 flex gap-2"><button class="flex-1 rounded-lg bg-emerald-600 p-2 font-semibold text-white" :disabled="saving" @click="selectAndUpdate(item,{status:'approved'})">Aprovar</button><button class="flex-1 rounded-lg bg-red-600 p-2 font-semibold text-white" :disabled="saving" @click="selectAndUpdate(item,{status:'rejected'})">Rejeitar</button></div></article><p v-if="!filteredRequests.length" class="rounded-2xl border bg-white p-8 text-center text-slate-500 lg:col-span-2">Nenhuma aprovação com os filtros atuais.</p></div>
    </section>

    <!-- Cancelamentos e alterações: fluxo próprio e rastreável. -->
    <section v-if="tab === 'changes'" class="mt-4 space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4"><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Solicitações</p><strong class="text-2xl">{{changeStats.total}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Alterações</p><strong class="text-2xl text-blue-600">{{changeStats.changes}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Cancelamentos</p><strong class="text-2xl text-red-600">{{changeStats.cancellations}}</strong></article><article class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Em tratamento</p><strong class="text-2xl text-amber-600">{{changeStats.active}}</strong></article></div>
      <article class="rounded-2xl border bg-white p-4 shadow-sm"><div class="overflow-x-auto"><table class="w-full min-w-[920px] text-sm"><thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Solicitação</th><th>Tipo</th><th>Cliente</th><th>Pedido</th><th>Motivo / descrição</th><th>Status</th><th>Responsável</th><th>Ações</th></tr></thead><tbody><tr v-for="item in filteredRequests" :key="item.id" class="border-b"><td class="p-3 font-semibold text-blue-700"><button @click="openRequest(item)">{{item.request_number}}</button></td><td>{{item.request_kind==='cancellation'?'Cancelamento':'Alteração'}}</td><td>{{item.contact?.name||'Sem contato'}}</td><td>{{item.order?.order_number}}</td><td class="max-w-[280px] truncate">{{item.description||'Sem descrição'}}</td><td>{{requestStatusLabel(item.status)}}</td><td>{{item.owner?.name||'Sem responsável'}}</td><td><div class="flex gap-1"><button v-if="!['completed','canceled','rejected'].includes(item.status)" class="rounded border border-emerald-300 px-2 py-1 text-emerald-700" :disabled="saving" @click="selectAndUpdate(item,{status:'approved'})">Aprovar</button><button v-if="!['completed','canceled','rejected'].includes(item.status)" class="rounded border border-red-300 px-2 py-1 text-red-700" :disabled="saving" @click="selectAndUpdate(item,{status:item.request_kind==='cancellation'?'canceled':'rejected'})">Recusar</button><button v-else class="rounded border px-2 py-1" :disabled="saving" @click="reopenRequest(item)">Reabrir</button></div></td></tr></tbody></table><p v-if="!filteredRequests.length" class="py-10 text-center text-slate-500">Nenhuma alteração ou cancelamento encontrado.</p></div></article>
    </section>

      </main>
    </div>

    <div
      v-if="showForm"
      class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4"
      @click.self="showForm = false"
    >
      <form
        class="w-full max-w-xl rounded-lg bg-white p-5 shadow-xl"
        @submit.prevent="saveRequest"
      >
        <div class="flex justify-between">
          <h3 class="text-lg font-bold">Nova solicitação</h3>
          <button type="button" title="Fechar" @click="showForm = false">
            ×
          </button>
        </div>
        <div class="mt-4 grid gap-3 sm:grid-cols-2">
          <label class="sm:col-span-2">
            Pedido de origem
            <select
              v-model="form.sales_order_id"
              required
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option disabled value="">Selecione</option>
              <option v-for="order in orders" :key="order.id" :value="order.id">
                {{ order.order_number }} ·
                {{ order.contact?.name || 'Sem contato' }} ·
                {{ money(order.total_cents) }}
              </option>
            </select>
          </label>
          <label>
            Tipo
            <select
              v-model="form.request_kind"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="change">Alteração</option>
              <option value="cancellation">Cancelamento</option>
              <option value="approval">Aprovação</option>
              <option value="fulfillment">Implantação</option>
            </select>
          </label>
          <label>
            Prioridade
            <select
              v-model="form.priority"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="low">Baixa</option>
              <option value="normal">Normal</option>
              <option value="high">Alta</option>
              <option value="critical">Crítica</option>
            </select>
          </label>
          <label class="sm:col-span-2">
            Título
            <input
              v-model="form.title"
              required
              class="mt-1 w-full rounded-lg border p-2"
            />
          </label>
          <label>
            Prazo
            <input
              v-model="form.due_at"
              type="datetime-local"
              class="mt-1 w-full rounded-lg border p-2"
            />
          </label>
          <label class="sm:col-span-2">
            Descrição
            <textarea
              v-model="form.description"
              rows="3"
              class="mt-1 w-full rounded-lg border p-2"
            />
          </label>
        </div>
        <div class="mt-5 flex justify-end gap-2">
          <button
            type="button"
            class="rounded-lg border px-4 py-2"
            @click="showForm = false"
          >
            Cancelar
          </button>
          <button
            class="rounded-lg bg-emerald-600 px-4 py-2 font-semibold text-white"
            :disabled="saving"
          >
            {{ saving ? 'Salvando...' : 'Criar solicitação' }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
