<script setup>
/* eslint-disable vue/no-bare-strings-in-template */
import { computed, onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { contractsAPI } from 'dashboard/api/crm/commercialCycle';
import { useAlert } from 'dashboard/composables';
import { crmControlClasses } from '../../crmControlClasses';

const router = useRouter();
const route = useRoute();

const rows = ref([]);
const loading = ref(false);
const q = ref('');
const status = ref('all');
const owner = ref('all');
const validity = ref('all');
const dealFilter = ref('all');
const page = ref(1);
const perPage = ref(10);
const saving = ref(false);
const signatureContract = ref(null);
const signedByName = ref('');
const signedAt = ref(new Date().toISOString().slice(0,16));
const signedFile = ref(null);
const signatureProvider = ref('');
const signatureExternalId = ref('');
const manageContract = ref(null);
const manageTab = ref('summary');
const contractHistory = ref([]);
const contractFiles = ref([]);
const contractUploadFiles = ref([]);
const detailLoading = ref(false);
const renewStartsOn = ref('');
const renewTermMonths = ref(12);
const addendumTitle = ref('');
const addendumNotes = ref('');

const money = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format((Number(value) || 0) / 100);

const date = value =>
  value
    ? new Intl.DateTimeFormat('pt-BR').format(
        new Date(`${value}T12:00:00`)
      )
    : '—';

const days = value =>
  value
    ? Math.ceil(
        (new Date(`${value}T23:59:59`) - new Date()) / 86400000
      )
    : 99999;

const normalized = contract => {
  const remainingDays = days(contract.ends_on);

  if (contract.status === 'active' && remainingDays < 0) {
    return 'ended';
  }

  if (
    contract.status === 'active' &&
    remainingDays >= 0 &&
    remainingDays <= 30
  ) {
    return 'expiring';
  }

  return contract.status;
};

const filtered = computed(() =>
  rows.value.filter(contract => {
    const currentStatus = normalized(contract);

    const text = `
      ${contract.contract_number || ''}
      ${contract.contact?.name || ''}
      ${contract.deal?.title || ''}
      ${contract.sales_order?.order_number || ''}
      ${contract.owner?.name || ''}
    `.toLowerCase();

    return (
      (!q.value || text.includes(q.value.toLowerCase())) &&
      (status.value === 'all' || currentStatus === status.value) &&
      (owner.value === 'all' ||
        String(contract.owner?.id) === owner.value) &&
      (dealFilter.value === 'all' ||
        String(contract.deal?.id || '') === dealFilter.value) &&
      (validity.value === 'all' ||
        (validity.value === '30' && days(contract.ends_on) >= 0 && days(contract.ends_on) <= 30) ||
        (validity.value === '60' && days(contract.ends_on) >= 0 && days(contract.ends_on) <= 60) ||
        (validity.value === '90' && days(contract.ends_on) >= 0 && days(contract.ends_on) <= 90) ||
        (validity.value === 'expired' && days(contract.ends_on) < 0))
    );
  })
);

const stats = computed(() => ({
  total: rows.value.length,

  active: rows.value.filter(
    contract => normalized(contract) === 'active'
  ).length,

  expiring: rows.value.filter(
    contract => normalized(contract) === 'expiring'
  ).length,

  ended: rows.value.filter(
    contract => normalized(contract) === 'ended'
  ).length,

  awaiting: rows.value.filter(
    contract => normalized(contract) === 'awaiting_signature'
  ).length,

  monthly: rows.value
    .filter(contract =>
      ['active', 'expiring'].includes(normalized(contract))
    )
    .reduce(
      (total, contract) =>
        total + (Number(contract.monthly_cents) || 0),
      0
    ),
}));

const owners = computed(() => [
  ...new Map(
    rows.value
      .filter(contract => contract.owner)
      .map(contract => [contract.owner.id, contract.owner])
  ).values(),
]);

const deals = computed(() => [
  ...new Map(
    rows.value
      .filter(contract => contract.deal)
      .map(contract => [contract.deal.id, contract.deal])
  ).values(),
]);
const pageCount = computed(() => Math.max(1, Math.ceil(filtered.value.length / perPage.value)));
const pagedContracts = computed(() => {
  const start = (page.value - 1) * perPage.value;
  return filtered.value.slice(start, start + perPage.value);
});

const load = async () => {
  loading.value = true;

  try {
    const response = await contractsAPI.list();
    rows.value = response.data || [];
  } finally {
    loading.value = false;
  }
};

onMounted(async () => {
  await load();
  const requested = rows.value.find(contract => String(contract.id) === String(route.query.contractId));
  if (requested) await openManage(requested);
});

const badge = value =>
  ({
    active:
      'border-emerald-200 bg-emerald-50 text-emerald-700',
    expiring:
      'border-amber-200 bg-amber-50 text-amber-700',
    ended:
      'border-red-200 bg-red-50 text-red-700',
    awaiting_signature:
      'border-blue-200 bg-blue-50 text-blue-700',
    draft:
      'border-slate-200 bg-slate-100 text-slate-700',
    renewed:
      'border-violet-200 bg-violet-50 text-violet-700',
  })[value] ||
  'border-slate-200 bg-slate-100 text-slate-700';

const label = value =>
  ({
    active: 'Ativo',
    expiring: 'A vencer',
    ended: 'Vencido',
    awaiting_signature: 'Aguardando assinatura',
    draft: 'Rascunho',
    renewed: 'Renovado',
  })[value] || value;

const statusIcon = value =>
  ({
    active: 'i-lucide-circle-check',
    expiring: 'i-lucide-clock-3',
    ended: 'i-lucide-circle-x',
    awaiting_signature: 'i-lucide-pen-line',
    draft: 'i-lucide-file-pen-line',
    renewed: 'i-lucide-refresh-cw',
  })[value] || 'i-lucide-circle';

const clearFilters = () => {
  q.value = '';
  status.value = 'all';
  owner.value = 'all';
  validity.value = 'all';
  dealFilter.value = 'all';
  page.value = 1;
};

const filterByStatus = value => {
  status.value = status.value === value ? 'all' : value;
};

const newContract = () => {
  router.push({
    name: 'crm_contract_new',
  });
};

const downloadPdf = async contract => {
  try {
    const { data } = await contractsAPI.pdf(contract.id);
    const url = URL.createObjectURL(data);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${contract.contract_number || `contrato-${contract.id}`}.pdf`;
    a.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    useAlert('Não foi possível gerar o PDF do contrato.');
  }
};


const openSignature = contract => {
  signatureContract.value = contract;
  signedByName.value = '';
  signedAt.value = new Date().toISOString().slice(0,16);
  signedFile.value = null;
  signatureProvider.value = contract.signature_provider || '';
  signatureExternalId.value = contract.signature_external_id || '';
};
const prepareSignature = async mode => {
  if (!signatureContract.value) return;
  saving.value = true;
  try {
    const { data } = await contractsAPI.prepareSignature(signatureContract.value.id, { mode, provider: mode === 'provider' ? signatureProvider.value : null });
    signatureContract.value = data; await load();
    if (manageContract.value?.id === data.id) await refreshManagedContract(data.id);
    useAlert(mode === 'manual' ? 'Assinatura manual preparada.' : 'Fluxo de provedor preparado; nenhum envio externo foi simulado.');
  } catch (error) { useAlert(error.response?.data?.message || 'Não foi possível preparar a assinatura.'); } finally { saving.value = false; }
};
const registerManualSignature = async () => {
  if (!signatureContract.value || !signedByName.value.trim()) { useAlert('Informe quem assinou.'); return; }
  saving.value = true;
  try {
    const { data } = await contractsAPI.registerManualSignature(signatureContract.value.id, { signed_by_name: signedByName.value, signed_at: signedAt.value, signed_file: signedFile.value });
    signatureContract.value = data; await load(); if (manageContract.value?.id === data.id) await refreshManagedContract(data.id); useAlert('Assinatura manual registrada.');
  } catch (error) { useAlert(error.response?.data?.message || 'Não foi possível registrar a assinatura.'); } finally { saving.value = false; }
};
const registerProviderResult = async () => {
  if (!signatureContract.value || !signatureExternalId.value.trim()) { useAlert('Informe o ID retornado pelo provedor após envio real.'); return; }
  saving.value = true;
  try {
    const { data } = await contractsAPI.sendForSignature(signatureContract.value.id, { external_id: signatureExternalId.value });
    signatureContract.value = data; await load(); if (manageContract.value?.id === data.id) await refreshManagedContract(data.id); useAlert('Envio externo registrado; assinatura ainda não foi concluída.');
  } catch (error) { useAlert(error.response?.data?.message || 'Não foi possível registrar o envio externo.'); } finally { saving.value = false; }
};


const refreshManagedContract = async id => {
  const [{ data: detail }, { data: history }] = await Promise.all([
    contractsAPI.show(id),
    contractsAPI.history(id),
  ]);
  manageContract.value = detail;
  contractFiles.value = detail.documents || [];
  contractHistory.value = history || [];
};

const openManage = async contract => {
  detailLoading.value = true;
  manageTab.value = 'summary';
  try {
    await refreshManagedContract(contract.id);
    const baseDate = manageContract.value?.ends_on
      ? new Date(`${manageContract.value.ends_on}T12:00:00`)
      : new Date();
    baseDate.setDate(baseDate.getDate() + 1);
    renewStartsOn.value = baseDate.toISOString().slice(0, 10);
    renewTermMonths.value =
      Number(
        manageContract.value?.renewal_term_months ||
          manageContract.value?.term_months ||
          12
      ) || 12;
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        'Não foi possível carregar os detalhes do contrato.'
    );
  } finally {
    detailLoading.value = false;
  }
};

const uploadContractDocuments = async () => {
  if (!manageContract.value || !contractUploadFiles.value.length) {
    useAlert('Selecione ao menos um documento.');
    return;
  }
  saving.value = true;
  try {
    await contractsAPI.uploadDocuments(
      manageContract.value.id,
      contractUploadFiles.value
    );
    contractUploadFiles.value = [];
    await refreshManagedContract(manageContract.value.id);
    await load();
    useAlert('Documento anexado e persistido.');
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        'Não foi possível enviar os documentos.'
    );
  } finally {
    saving.value = false;
  }
};

const downloadContractDocument = async documentRow => {
  if (!manageContract.value) return;
  try {
    const { data } = await contractsAPI.downloadDocument(
      manageContract.value.id,
      documentRow.id
    );
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = documentRow.filename || `documento-${documentRow.id}`;
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    useAlert('Não foi possível baixar o documento.');
  }
};

const downloadSignedDocument = async () => {
  if (!manageContract.value?.signed_document) {
    useAlert('Este contrato não possui documento assinado anexado.');
    return;
  }
  try {
    const { data } = await contractsAPI.downloadSignedDocument(manageContract.value.id);
    const url = URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download =
      manageContract.value.signed_document.filename ||
      `contrato-assinado-${manageContract.value.contract_number || manageContract.value.id}.pdf`;
    link.click();
    URL.revokeObjectURL(url);
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        'Não foi possível baixar o documento assinado.'
    );
  }
};

const renewContract = async () => {
  if (!manageContract.value) return;
  saving.value = true;
  try {
    const { data } = await contractsAPI.renew(manageContract.value.id, {
      starts_on: renewStartsOn.value || null,
      term_months: Number(renewTermMonths.value || 12),
    });
    await load();
    await openManage(data);
    manageTab.value = 'summary';
    useAlert('Renovação criada como novo contrato em rascunho.');
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        error.response?.data?.errors?.join(', ') ||
        'Não foi possível criar a renovação.'
    );
  } finally {
    saving.value = false;
  }
};

const createAddendum = async () => {
  if (!manageContract.value) return;
  if (!addendumTitle.value.trim()) {
    useAlert('Informe o título do aditivo.');
    return;
  }
  saving.value = true;
  try {
    await contractsAPI.addendum(manageContract.value.id, {
      title: addendumTitle.value.trim(),
      notes: addendumNotes.value.trim(),
    });
    addendumTitle.value = '';
    addendumNotes.value = '';
    await refreshManagedContract(manageContract.value.id);
    await load();
    useAlert('Aditivo registrado no histórico do contrato.');
  } catch (error) {
    useAlert(
      error.response?.data?.message ||
        'Não foi possível registrar o aditivo.'
    );
  } finally {
    saving.value = false;
  }
};

const openManageSignature = () => {
  if (!manageContract.value) return;
  openSignature(manageContract.value);
};

const updateStatus = async (contract, nextStatus) => {
  saving.value = true;
  try {
    await contractsAPI.update(contract.id, { contract: { status: nextStatus } });
    await load();
    useAlert('Contrato atualizado.');
  } catch (error) {
    useAlert(error.response?.data?.errors?.join(', ') || 'Não foi possível atualizar o contrato.');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="h-full overflow-auto bg-[#f6f8fc] dark:bg-n-background">
    <!-- CABEÇALHO -->
    <header
      class="border-b border-slate-200 bg-white px-5 py-5 sm:px-6"
    >
      <div
        class="mx-auto flex max-w-[1600px] flex-wrap items-center justify-between gap-4"
      >
        <div class="flex items-center gap-4">
          <span
            class="grid size-12 place-content-center rounded-2xl bg-gradient-to-br from-blue-600 to-indigo-600 text-white shadow-lg shadow-blue-200"
          >
            <i class="i-lucide-file-text size-6" />
          </span>

          <div>
            <div class="flex flex-wrap items-center gap-2">
              <h2 class="text-2xl font-bold text-slate-900">
                Contratos
              </h2>

              <span
                class="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-semibold text-blue-700"
              >
                {{ stats.total }} cadastrados
              </span>
            </div>

            <p class="mt-1 text-sm text-slate-500">
              Gestão de contratos, vigência, renovações e relacionamento
              com clientes.
            </p>
          </div>
        </div>

        <button
          type="button"
          class="flex items-center gap-2 rounded-xl bg-blue-600 px-5 py-3 text-sm font-semibold text-white shadow-lg shadow-blue-200 transition hover:bg-blue-700"
          @click="newContract"
        >
          <i class="i-lucide-plus size-5" />
          Novo contrato
        </button>
      </div>
    </header>

    <main class="mx-auto max-w-[1600px] p-5 sm:p-6">
      <!-- DASHBOARD -->
      <section
        class="mb-5 grid gap-4 sm:grid-cols-2 xl:grid-cols-5"
      >
        <!-- TOTAL -->
        <button
          type="button"
          class="group rounded-2xl border border-blue-100 bg-gradient-to-br from-white to-blue-50 p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          @click="status = 'all'"
        >
          <div class="flex items-start justify-between">
            <span
              class="grid size-11 place-content-center rounded-xl bg-blue-100 text-blue-700"
            >
              <i class="i-lucide-files size-5" />
            </span>

            <i
              class="i-lucide-arrow-up-right size-4 text-blue-400 opacity-0 transition group-hover:opacity-100"
            />
          </div>

          <p class="mt-5 text-sm font-medium text-slate-500">
            Total de contratos
          </p>

          <strong class="mt-1 block text-3xl font-bold text-slate-900">
            {{ stats.total }}
          </strong>
        </button>

        <!-- ATIVOS -->
        <button
          type="button"
          class="group rounded-2xl border border-emerald-100 bg-gradient-to-br from-white to-emerald-50 p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          @click="filterByStatus('active')"
        >
          <div class="flex items-start justify-between">
            <span
              class="grid size-11 place-content-center rounded-xl bg-emerald-100 text-emerald-700"
            >
              <i class="i-lucide-circle-check size-5" />
            </span>

            <span
              class="rounded-full bg-emerald-100 px-2 py-1 text-xs font-semibold text-emerald-700"
            >
              Vigentes
            </span>
          </div>

          <p class="mt-5 text-sm font-medium text-slate-500">
            Contratos ativos
          </p>

          <strong
            class="mt-1 block text-3xl font-bold text-emerald-700"
          >
            {{ stats.active }}
          </strong>
        </button>

        <!-- A VENCER -->
        <button
          type="button"
          class="group rounded-2xl border border-amber-100 bg-gradient-to-br from-white to-amber-50 p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          @click="filterByStatus('expiring')"
        >
          <div class="flex items-start justify-between">
            <span
              class="grid size-11 place-content-center rounded-xl bg-amber-100 text-amber-700"
            >
              <i class="i-lucide-clock-3 size-5" />
            </span>

            <span
              class="rounded-full bg-amber-100 px-2 py-1 text-xs font-semibold text-amber-700"
            >
              30 dias
            </span>
          </div>

          <p class="mt-5 text-sm font-medium text-slate-500">
            A vencer
          </p>

          <strong
            class="mt-1 block text-3xl font-bold text-amber-700"
          >
            {{ stats.expiring }}
          </strong>
        </button>

        <!-- VENCIDOS -->
        <button
          type="button"
          class="group rounded-2xl border border-red-100 bg-gradient-to-br from-white to-red-50 p-5 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          @click="filterByStatus('ended')"
        >
          <div class="flex items-start justify-between">
            <span
              class="grid size-11 place-content-center rounded-xl bg-red-100 text-red-700"
            >
              <i class="i-lucide-circle-x size-5" />
            </span>
          </div>

          <p class="mt-5 text-sm font-medium text-slate-500">
            Vencidos
          </p>

          <strong
            class="mt-1 block text-3xl font-bold text-red-700"
          >
            {{ stats.ended }}
          </strong>
        </button>

        <!-- MRR -->
        <article
          class="rounded-2xl border border-violet-100 bg-gradient-to-br from-violet-600 to-indigo-700 p-5 text-white shadow-lg shadow-violet-100"
        >
          <div class="flex items-start justify-between">
            <span
              class="grid size-11 place-content-center rounded-xl bg-white/15"
            >
              <i class="i-lucide-badge-dollar-sign size-5" />
            </span>

            <span
              class="rounded-full bg-white/15 px-2 py-1 text-xs font-semibold"
            >
              Receita mensal
            </span>
          </div>

          <p class="mt-5 text-sm font-medium text-violet-100">
            MRR contratado
          </p>

          <strong class="mt-1 block text-2xl font-bold">
            {{ money(stats.monthly) }}
          </strong>
        </article>
      </section>

      <!-- ALERTA DE ASSINATURA -->
      <section
        v-if="stats.awaiting > 0"
        class="mb-5 flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-blue-200 bg-blue-50 px-5 py-4"
      >
        <div class="flex items-center gap-3">
          <span
            class="grid size-10 place-content-center rounded-xl bg-blue-100 text-blue-700"
          >
            <i class="i-lucide-pen-line size-5" />
          </span>

          <div>
            <p class="font-semibold text-blue-900">
              Contratos aguardando assinatura
            </p>

            <p class="text-sm text-blue-700">
              Existem {{ stats.awaiting }} contrato(s) aguardando
              assinatura.
            </p>
          </div>
        </div>

        <button
          type="button"
          class="rounded-lg border border-blue-200 bg-white px-4 py-2 text-sm font-semibold text-blue-700"
          @click="status = 'awaiting_signature'"
        >
          Visualizar
        </button>
      </section>

      <!-- LISTAGEM -->
      <section
        class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
      >
        <!-- TÍTULO -->
        <div
          class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-5 py-4"
        >
          <div>
            <h3 class="font-bold text-slate-900">
              Todos os contratos
            </h3>

            <p class="text-sm text-slate-500">
              {{ filtered.length }} resultado(s) encontrado(s)
            </p>
          </div>

          <button
            type="button"
            class="flex items-center gap-2 rounded-lg border border-slate-200 bg-white px-3 py-2 text-sm font-medium text-slate-600 transition hover:bg-slate-50"
            @click="load"
          >
            <i
              class="i-lucide-refresh-cw size-4"
              :class="{ 'animate-spin': loading }"
            />
            Atualizar
          </button>
        </div>

        <!-- FILTROS -->
        <div
          class="grid gap-3 border-b border-slate-200 bg-slate-50/60 p-4 xl:grid-cols-[1.4fr_.7fr_.8fr_.8fr_.8fr_auto]"
        >
          <label class="relative">
            <i
              class="i-lucide-search absolute left-3 top-1/2 size-4 -translate-y-1/2 text-slate-400"
            />

            <input
              v-model="q"
              class="w-full rounded-xl border border-slate-200 bg-white py-2.5 pl-10 pr-3 text-sm outline-none transition focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
              placeholder="Buscar cliente, contrato, venda ou responsável..."
            />
          </label>

          <select
            v-model="status"
            class="rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-blue-400"
          >
            <option value="all">
              Todos os status
            </option>
            <option value="active">
              Ativos
            </option>
            <option value="expiring">
              A vencer
            </option>
            <option value="ended">
              Vencidos
            </option>
            <option value="awaiting_signature">
              Aguardando assinatura
            </option>
            <option value="draft">
              Rascunho
            </option>
            <option value="renewed">
              Renovados
            </option>
          </select>

          <select
            v-model="owner"
            class="rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-blue-400"
          >
            <option value="all">
              Todos os responsáveis
            </option>

            <option
              v-for="responsible in owners"
              :key="responsible.id"
              :value="String(responsible.id)"
            >
              {{ responsible.name }}
            </option>
          </select>

          <select v-model="validity" class="rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-blue-400">
            <option value="all">Todas as vigências</option>
            <option value="30">Vence em 30 dias</option>
            <option value="60">Vence em 60 dias</option>
            <option value="90">Vence em 90 dias</option>
            <option value="expired">Vencidos</option>
          </select>

          <select v-model="dealFilter" class="rounded-xl border border-slate-200 bg-white px-3 py-2.5 text-sm outline-none focus:border-blue-400">
            <option value="all">Todos os negócios</option>
            <option v-for="dealItem in deals" :key="dealItem.id" :value="String(dealItem.id)">{{ dealItem.title }}</option>
          </select>

          <button
            type="button"
            class="flex items-center justify-center gap-2 rounded-xl border border-blue-200 bg-white px-4 py-2.5 text-sm font-semibold text-blue-700 transition hover:bg-blue-50"
            @click="clearFilters"
          >
            <i class="i-lucide-filter-x size-4" />
            Limpar
          </button>
        </div>

        <!-- TABELA -->
        <div class="overflow-x-auto">
          <table class="w-full min-w-[1100px] text-sm">
            <thead
              class="bg-slate-50 text-left text-xs font-semibold uppercase tracking-wide text-slate-500"
            >
              <tr>
                <th class="p-4">
                  Contrato / Cliente
                </th>

                <th class="p-4">
                  Negócio / Venda
                </th>

                <th class="p-4">
                  Produtos / Serviços
                </th>

                <th class="p-4">
                  Vigência
                </th>

                <th class="p-4">
                  MRR
                </th>

                <th class="p-4">
                  Status
                </th>

                <th class="p-4">Responsável</th>
                <th class="p-4 text-right">Ações</th>
              </tr>
            </thead>

            <tbody class="divide-y divide-slate-100">
              <!-- LOADING -->
              <tr v-if="loading">
                <td
                  colspan="8"
                  class="p-14 text-center"
                >
                  <div
                    class="mx-auto mb-3 grid size-12 place-content-center rounded-full bg-blue-50 text-blue-600"
                  >
                    <i
                      class="i-lucide-loader-circle size-6 animate-spin"
                    />
                  </div>

                  <p class="font-medium text-slate-700">
                    Carregando contratos...
                  </p>
                </td>
              </tr>

              <!-- REGISTROS -->
              <tr
                v-for="contract in pagedContracts"
                v-else
                :key="contract.id"
                class="transition hover:bg-blue-50/40"
              >
                <!-- CONTRATO -->
                <td class="p-4">
                  <div class="flex items-center gap-3">
                    <span
                      class="grid size-10 shrink-0 place-content-center rounded-xl bg-blue-50 text-blue-600"
                    >
                      <i class="i-lucide-file-text size-5" />
                    </span>

                    <div>
                      <strong
                        class="font-semibold text-slate-900"
                      >
                        {{ contract.contract_number || `#${contract.id}` }}
                      </strong>

                      <p class="mt-0.5 text-xs text-slate-500">
                        {{ contract.contact?.name || 'Cliente não informado' }}
                      </p>
                    </div>
                  </div>
                </td>

                <!-- NEGÓCIO -->
                <td class="p-4">
                  <p class="font-medium text-slate-700">
                    {{ contract.deal?.title || 'Pedido direto' }}
                  </p>

                  <p
                    v-if="contract.sales_order?.order_number"
                    class="mt-1 text-xs font-medium text-blue-600"
                  >
                    <i
                      class="i-lucide-shopping-cart mr-1"
                    />
                    {{ contract.sales_order.order_number }}
                  </p>

                  <p
                    v-else
                    class="mt-1 text-xs text-slate-400"
                  >
                    Sem pedido vinculado
                  </p>
                </td>

                <!-- PRODUTOS -->
                <td class="p-4">
                  <div class="flex items-center gap-2 text-slate-600">
                    <span
                      class="grid size-8 place-content-center rounded-lg bg-violet-50 text-violet-600"
                    >
                      <i class="i-lucide-package size-4" />
                    </span>

                    <span>
                      Itens vinculados ao pedido
                    </span>
                  </div>
                </td>

                <!-- VIGÊNCIA -->
                <td class="p-4">
                  <div class="flex items-start gap-2">
                    <i
                      class="i-lucide-calendar-days mt-0.5 size-4 text-slate-400"
                    />

                    <div>
                      <p class="font-medium text-slate-700">
                        {{ date(contract.starts_on) }}
                      </p>

                      <p class="text-xs text-slate-500">
                        até {{ date(contract.ends_on) }}
                      </p>
                    </div>
                  </div>
                </td>

                <!-- MRR -->
                <td class="p-4">
                  <strong
                    class="text-base font-bold text-indigo-700"
                  >
                    {{ money(contract.monthly_cents) }}
                  </strong>

                  <p class="text-xs text-slate-400">
                    por mês
                  </p>
                </td>

                <!-- STATUS -->
                <td class="p-4">
                  <span
                    :class="badge(normalized(contract))"
                    class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-semibold"
                  >
                    <i
                      :class="statusIcon(normalized(contract))"
                      class="size-3.5"
                    />

                    {{ label(normalized(contract)) }}
                  </span>
                </td>

                <!-- RESPONSÁVEL -->
                <td class="p-4">
                  <div
                    v-if="contract.owner"
                    class="flex items-center gap-2"
                  >
                    <span
                      class="grid size-8 place-content-center rounded-full bg-indigo-100 text-xs font-bold text-indigo-700"
                    >
                      {{
                        contract.owner.name
                          ?.charAt(0)
                          ?.toUpperCase()
                      }}
                    </span>

                    <span
                      class="font-medium text-slate-700"
                    >
                      {{ contract.owner.name }}
                    </span>
                  </div>

                  <span
                    v-else
                    class="text-slate-400"
                  >
                    Não definido
                  </span>
                </td>
                <td class="p-4">
                  <div class="flex justify-end gap-1.5">
                    <button title="Gerenciar contrato" class="grid size-9 place-content-center rounded-lg border border-violet-200 text-violet-600 hover:bg-violet-50" @click="openManage(contract)">
                      <i class="i-lucide-panel-right-open size-4" />
                    </button>
                    <button title="Baixar PDF" class="grid size-9 place-content-center rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50" @click="downloadPdf(contract)">
                      <i class="i-lucide-file-down size-4" />
                    </button>
                    <button v-if="normalized(contract)==='draft'" title="Enviar para assinatura" :disabled="saving" class="grid size-9 place-content-center rounded-lg border border-blue-200 text-blue-600 hover:bg-blue-50" @click="updateStatus(contract,'awaiting_signature')">
                      <i class="i-lucide-send size-4" />
                    </button>
                    <button v-if="normalized(contract)==='awaiting_signature'" title="Gerenciar assinatura" :disabled="saving" class="grid size-9 place-content-center rounded-lg border border-emerald-200 text-emerald-600 hover:bg-emerald-50" @click="openSignature(contract)">
                      <i class="i-lucide-check size-4" />
                    </button>
                  </div>
                </td>
              </tr>

              <!-- VAZIO -->
              <tr
                v-if="!loading && !filtered.length"
              >
                <td
                  colspan="8"
                  class="px-6 py-16 text-center"
                >
                  <div
                    class="mx-auto grid size-16 place-content-center rounded-2xl bg-blue-50 text-blue-600"
                  >
                    <i class="i-lucide-file-search size-8" />
                  </div>

                  <h3
                    class="mt-4 text-base font-bold text-slate-900"
                  >
                    Nenhum contrato encontrado
                  </h3>

                  <p
                    v-if="rows.length"
                    class="mx-auto mt-1 max-w-md text-sm text-slate-500"
                  >
                    Nenhum contrato corresponde aos filtros selecionados.
                  </p>

                  <p
                    v-else
                    class="mx-auto mt-1 max-w-md text-sm text-slate-500"
                  >
                    Você ainda não possui contratos cadastrados.
                    Crie o primeiro contrato para iniciar a gestão.
                  </p>

                  <div
                    class="mt-5 flex justify-center gap-2"
                  >
                    <button
                      v-if="rows.length"
                      type="button"
                      class="rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-sm font-semibold text-slate-700"
                      @click="clearFilters"
                    >
                      Limpar filtros
                    </button>

                    <button
                      type="button"
                      class="inline-flex items-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white shadow"
                      @click="newContract"
                    >
                      <i class="i-lucide-plus size-4" />
                      Novo contrato
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div v-if="filtered.length" class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-200 bg-slate-50/60 px-4 py-3">
          <span class="text-xs text-slate-500">Página {{ page }} de {{ pageCount }} · {{ filtered.length }} contrato(s)</span>
          <div class="flex items-center gap-2">
            <select v-model.number="perPage" class="rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-xs" @change="page=1">
              <option :value="10">10 por página</option>
              <option :value="20">20 por página</option>
              <option :value="50">50 por página</option>
            </select>
            <button class="rounded-lg border bg-white px-3 py-1.5 text-xs font-semibold disabled:opacity-40" :disabled="page<=1" @click="page--">Anterior</button>
            <button class="rounded-lg border bg-white px-3 py-1.5 text-xs font-semibold disabled:opacity-40" :disabled="page>=pageCount" @click="page++">Próxima</button>
          </div>
        </div>
      </section>
    </main>

    <Teleport to="body">
      <div :class="crmControlClasses" v-if="manageContract" class="fixed inset-0 z-[95] flex justify-end bg-black/40" @click.self="manageContract=null">
        <section class="h-full w-full max-w-4xl overflow-y-auto bg-slate-50 shadow-2xl">
          <div class="sticky top-0 z-10 border-b bg-white px-5 py-4">
            <div class="flex items-start justify-between gap-4">
              <div>
                <p class="text-xs font-semibold uppercase tracking-wide text-violet-600">Gestão do contrato</p>
                <h3 class="text-xl font-bold">{{ manageContract.contract_number }}</h3>
                <p class="text-sm text-slate-500">{{ manageContract.contact?.name || 'Cliente' }} · {{ label(normalized(manageContract)) }}</p>
              </div>
              <button class="grid size-9 place-content-center rounded-lg border text-xl" @click="manageContract=null">×</button>
            </div>
            <nav class="mt-4 flex gap-2 overflow-x-auto">
              <button v-for="item in [['summary','Resumo'],['documents','Documentos'],['signature','Assinatura'],['addenda','Aditivos'],['renewal','Renovação'],['history','Histórico']]" :key="item[0]" class="shrink-0 rounded-lg px-3 py-2 text-sm font-semibold" :class="manageTab===item[0]?'bg-violet-600 text-white':'bg-slate-100 text-slate-600'" @click="manageTab=item[0]">{{item[1]}}</button>
            </nav>
          </div>

          <div v-if="detailLoading" class="p-10 text-center text-slate-500">Carregando detalhes...</div>
          <div v-else class="space-y-4 p-5">
            <template v-if="manageTab==='summary'">
              <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                <article class="rounded-xl border bg-white p-4"><p class="text-xs text-slate-500">Valor único</p><strong>{{money(manageContract.one_time_cents)}}</strong></article>
                <article class="rounded-xl border bg-white p-4"><p class="text-xs text-slate-500">MRR</p><strong>{{money(manageContract.monthly_cents)}}</strong></article>
                <article class="rounded-xl border bg-white p-4"><p class="text-xs text-slate-500">Vigência</p><strong>{{date(manageContract.starts_on)}} a {{date(manageContract.ends_on)}}</strong></article>
                <article class="rounded-xl border bg-white p-4"><p class="text-xs text-slate-500">Assinatura</p><strong>{{manageContract.signature_status || 'not_started'}}</strong></article>
              </div>
              <article class="rounded-2xl border bg-white p-5">
                <h4 class="font-bold">Vínculos</h4>
                <dl class="mt-4 grid gap-3 text-sm sm:grid-cols-2">
                  <div><dt class="text-slate-500">Pedido</dt><dd class="font-semibold">{{manageContract.sales_order?.order_number || '—'}}</dd></div>
                  <div><dt class="text-slate-500">Negócio</dt><dd class="font-semibold">{{manageContract.deal?.title || '—'}}</dd></div>
                  <div><dt class="text-slate-500">Responsável</dt><dd class="font-semibold">{{manageContract.owner?.name || '—'}}</dd></div>
                  <div><dt class="text-slate-500">Modelo</dt><dd class="font-semibold">{{manageContract.template?.name || manageContract.contract_template?.name || 'Sem modelo'}}</dd></div>
                </dl>
                <div class="mt-5 flex flex-wrap gap-2">
                  <button class="rounded-xl border px-4 py-2 text-sm font-semibold" @click="downloadPdf(manageContract)">Baixar PDF gerado</button>
                  <button class="rounded-xl border border-emerald-300 px-4 py-2 text-sm font-semibold text-emerald-700" @click="openManageSignature">Gerenciar assinatura</button>
                </div>
              </article>
            </template>

            <template v-else-if="manageTab==='documents'">
              <article class="rounded-2xl border bg-white p-5">
                <h4 class="font-bold">Documentos do contrato</h4>
                <p class="mt-1 text-xs text-slate-500">Arquivos enviados aqui ficam persistidos no ActiveStorage do contrato.</p>
                <div class="mt-4 flex flex-wrap items-center gap-2">
                  <input type="file" multiple class="min-w-0 flex-1 rounded-lg border p-2 text-sm" @change="contractUploadFiles=Array.from($event.target.files||[])" />
                  <button class="rounded-lg bg-violet-600 px-4 py-2 font-semibold text-white disabled:opacity-50" :disabled="saving || !contractUploadFiles.length" @click="uploadContractDocuments">Enviar</button>
                </div>
                <div class="mt-4 divide-y">
                  <div v-for="file in contractFiles" :key="file.id" class="flex items-center justify-between gap-3 py-3">
                    <div class="min-w-0"><p class="truncate font-semibold">{{file.filename}}</p><p class="text-xs text-slate-500">{{file.content_type}} · {{Math.ceil((file.byte_size||0)/1024)}} KB</p></div>
                    <button class="rounded-lg border px-3 py-1.5 text-sm" @click="downloadContractDocument(file)">Baixar</button>
                  </div>
                  <p v-if="!contractFiles.length" class="py-8 text-center text-sm text-slate-500">Nenhum documento adicional anexado.</p>
                </div>
              </article>
            </template>

            <template v-else-if="manageTab==='signature'">
              <article class="rounded-2xl border bg-white p-5">
                <h4 class="font-bold">Assinatura e acompanhamento</h4>
                <p class="mt-1 text-sm text-slate-500">Status atual: <b>{{manageContract.signature_status || 'not_started'}}</b>. Assinatura manual e provedor externo são fluxos distintos.</p>
                <div class="mt-4 grid gap-3 md:grid-cols-2">
                  <div class="rounded-xl border border-emerald-200 bg-emerald-50 p-4"><strong>Manual</strong><p class="mt-1 text-xs text-slate-600">Registre apenas quando o documento foi realmente assinado fora do provedor.</p></div>
                  <div class="rounded-xl border border-indigo-200 bg-indigo-50 p-4"><strong>Provedor externo</strong><p class="mt-1 text-xs text-slate-600">Preparar não significa enviar. O CRM só marca envio após receber um identificador real.</p></div>
                </div>
                <div v-if="manageContract.signed_document" class="mt-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-emerald-200 bg-emerald-50 p-4">
                  <div class="min-w-0">
                    <p class="text-xs font-semibold uppercase text-emerald-700">Documento assinado arquivado</p>
                    <p class="truncate text-sm font-semibold text-slate-800">{{ manageContract.signed_document.filename }}</p>
                    <p class="text-xs text-slate-500">{{ Math.ceil((manageContract.signed_document.byte_size || 0) / 1024) }} KB · disponível para recuperação</p>
                  </div>
                  <button class="rounded-lg border border-emerald-300 bg-white px-3 py-2 text-sm font-semibold text-emerald-700" @click="downloadSignedDocument">Baixar documento assinado</button>
                </div>
                <div v-else-if="manageContract.signature_status === 'signed'" class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm text-amber-800">
                  A assinatura está registrada, mas nenhum arquivo assinado foi anexado ao contrato.
                </div>
                <button class="mt-4 rounded-xl bg-emerald-600 px-4 py-2 font-semibold text-white" @click="openManageSignature">Abrir controles de assinatura</button>
              </article>
            </template>

            <template v-else-if="manageTab==='addenda'">
              <article class="rounded-2xl border bg-white p-5">
                <h4 class="font-bold">Aditivos</h4>
                <div class="mt-4 grid gap-3">
                  <input v-model="addendumTitle" class="rounded-lg border p-2.5" placeholder="Título do aditivo" />
                  <textarea v-model="addendumNotes" rows="4" class="rounded-lg border p-2.5" placeholder="Descreva o que foi alterado. O registro não substitui um documento jurídico assinado." />
                  <button class="w-fit rounded-lg bg-violet-600 px-4 py-2 font-semibold text-white" :disabled="saving" @click="createAddendum">Registrar aditivo</button>
                </div>
                <div class="mt-5 space-y-3">
                  <div v-for="item in (manageContract.lifecycle_metadata?.addenda || [])" :key="item.id" class="rounded-xl border p-4">
                    <div class="flex justify-between gap-3"><strong>{{item.title}}</strong><span class="text-xs text-slate-500">{{new Date(item.created_at).toLocaleString('pt-BR')}}</span></div>
                    <p class="mt-2 whitespace-pre-line text-sm text-slate-600">{{item.notes || 'Sem observações.'}}</p>
                  </div>
                  <p v-if="!(manageContract.lifecycle_metadata?.addenda || []).length" class="rounded-xl bg-slate-50 p-4 text-sm text-slate-500">Nenhum aditivo registrado.</p>
                </div>
              </article>
            </template>

            <template v-else-if="manageTab==='renewal'">
              <article class="rounded-2xl border bg-white p-5">
                <h4 class="font-bold">Renovação</h4>
                <p class="mt-1 text-sm text-slate-500">A renovação cria um novo contrato em rascunho vinculado ao contrato de origem; não altera silenciosamente a vigência antiga.</p>
                <div class="mt-4 grid gap-3 sm:grid-cols-2">
                  <label>Nova vigência a partir de<input v-model="renewStartsOn" type="date" class="mt-1 w-full rounded-lg border p-2" /></label>
                  <label>Prazo (meses)<input v-model.number="renewTermMonths" type="number" min="1" max="120" class="mt-1 w-full rounded-lg border p-2" /></label>
                </div>
                <button class="mt-4 rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white" :disabled="saving" @click="renewContract">Criar renovação em rascunho</button>
              </article>
            </template>

            <template v-else>
              <article class="rounded-2xl border bg-white p-5">
                <h4 class="font-bold">Histórico do contrato</h4>
                <div class="mt-4 space-y-3">
                  <div v-for="event in contractHistory" :key="event.id" class="rounded-xl border p-4">
                    <div class="flex flex-wrap items-center justify-between gap-2"><strong>{{event.event_type}}</strong><span class="text-xs text-slate-500">{{new Date(event.created_at).toLocaleString('pt-BR')}}</span></div>
                    <p class="mt-1 text-xs text-slate-500">Ator #{{event.actor_id || 'sistema'}}</p>
                  </div>
                  <p v-if="!contractHistory.length" class="py-8 text-center text-sm text-slate-500">Nenhum evento registrado.</p>
                </div>
              </article>
            </template>
          </div>
        </section>
      </div>
    </Teleport>

    <Teleport to="body">
      <div :class="crmControlClasses" v-if="signatureContract" class="fixed inset-0 z-[100] grid place-items-center bg-black/45 p-4" @click.self="signatureContract=null">
        <section class="w-full max-w-3xl rounded-2xl bg-white p-6 shadow-2xl">
          <div class="flex items-start justify-between"><div><p class="text-xs font-semibold uppercase text-blue-600">Assinatura do contrato</p><h3 class="text-xl font-bold">{{ signatureContract.contract_number }}</h3><p class="text-sm text-slate-500">Status real: {{ signatureContract.signature_status || 'not_started' }}</p></div><button class="text-2xl" @click="signatureContract=null">×</button></div>
          <div class="mt-5 grid gap-4 md:grid-cols-2">
            <div class="rounded-xl border border-emerald-200 bg-emerald-50/40 dark:bg-n-teal-3 p-4"><h4 class="font-bold">Assinatura manual</h4><p class="mt-1 text-xs text-slate-600">Registre somente depois que a assinatura realmente ocorrer.</p><button class="mt-3 rounded-lg border px-3 py-2 text-sm" @click="prepareSignature('manual')">Preparar assinatura manual</button><label class="mt-3 block text-sm">Assinado por<input v-model="signedByName" class="mt-1 w-full rounded-lg border p-2" /></label><label class="mt-3 block text-sm">Data/hora<input v-model="signedAt" type="datetime-local" class="mt-1 w-full rounded-lg border p-2" /></label><label class="mt-3 block text-sm">Documento assinado<input type="file" accept="application/pdf,image/*" class="mt-1 w-full rounded-lg border p-2" @change="signedFile=$event.target.files?.[0]||null" /></label><button class="mt-3 w-full rounded-lg bg-emerald-600 px-3 py-2 font-semibold text-white" :disabled="saving" @click="registerManualSignature">Registrar assinatura real</button></div>
            <div class="rounded-xl border border-indigo-200 bg-indigo-50/40 dark:bg-n-iris-3 p-4"><h4 class="font-bold">Provedor externo</h4><p class="mt-1 text-xs text-slate-600">Não há simulação: o ID abaixo deve vir do provedor após envio real.</p><label class="mt-3 block text-sm">Provedor<select v-model="signatureProvider" class="mt-1 w-full rounded-lg border p-2"><option value="">Selecione</option><option value="clicksign">Clicksign</option><option value="docusign">DocuSign</option><option value="zoho_sign">Zoho Sign</option><option value="other">Outro</option></select></label><button class="mt-3 w-full rounded-lg border border-indigo-300 px-3 py-2 font-semibold text-indigo-700" :disabled="!signatureProvider||saving" @click="prepareSignature('provider')">Preparar provedor</button><label class="mt-3 block text-sm">ID externo<input v-model="signatureExternalId" class="mt-1 w-full rounded-lg border p-2" /></label><button class="mt-3 w-full rounded-lg bg-indigo-600 px-3 py-2 font-semibold text-white" :disabled="!signatureExternalId||saving" @click="registerProviderResult">Registrar envio externo</button></div>
          </div>
        </section>
      </div>
    </Teleport>

  </div>
</template>