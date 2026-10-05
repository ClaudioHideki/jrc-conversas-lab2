<script setup>
/* eslint-disable vue/no-bare-strings-in-template */
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { salesOrdersAPI } from 'dashboard/api/crm/commercialCycle';
import { useAlert } from 'dashboard/composables';
import { crmControlClasses } from '../../crmControlClasses';

const route = useRoute();
const router = useRouter();
const rows = ref([]);
const loading = ref(false);
const selected = ref(null);
const saving = ref(false);
const search = ref('');
const statusFilter = ref('all');
const ownerFilter = ref('all');
const customerFilter = ref('all');
const periodFilter = ref('all');
const view = ref('list');
const page = ref(1);
const perPage = ref(10);
const selectedIds = ref([]);
const editingItems = ref(false);
const draftItems = ref([]);

const money = value =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    (Number(value) || 0) / 100
  );
const dateLabel = value =>
  value ? new Intl.DateTimeFormat('pt-BR').format(new Date(value)) : '—';
const statusLabel = status =>
  ({
    draft: 'Rascunho',
    pending: 'Pendente',
    approved: 'Aprovado',
    separating: 'Em implantação',
    invoiced: 'Faturado',
    shipped: 'Em entrega',
    completed: 'Ativo',
    canceled: 'Cancelado',
  })[status] || status;
const statusTone = status =>
  ({
    draft: 'bg-n-slate-3 text-n-slate-12',
    pending: 'bg-amber-50 text-amber-700',
    approved: 'bg-emerald-50 text-emerald-700',
    separating: 'bg-blue-50 text-blue-700',
    invoiced: 'bg-violet-50 text-violet-700',
    shipped: 'bg-cyan-50 text-cyan-700',
    completed: 'bg-emerald-50 text-emerald-700',
    canceled: 'bg-red-50 text-red-700',
  })[status] || 'bg-n-slate-3 text-n-slate-12';
const originLabel = origin =>
  ({
    proposal_deal: 'Proposta / Negócio',
    direct_sale: 'Venda direta',
    renewal: 'Renovação',
    expansion: 'Upgrade / Expansão',
  })[origin] ||
  origin ||
  '—';
const customerName = row =>
  row.contact?.name || row.snapshot?.customer_name || 'Cliente não informado';
const orderDate = row => row.sold_at || row.created_at;
const active = row => row.status !== 'canceled';

const owners = computed(() => [
  ...new Map(
    rows.value.filter(r => r.owner).map(r => [r.owner.id, r.owner])
  ).values(),
]);
const customers = computed(() =>
  [
    ...new Map(
      rows.value.map(r => [customerName(r), customerName(r)])
    ).values(),
  ].sort()
);
const periodMatch = row => {
  if (periodFilter.value === 'all') return true;
  const d = new Date(orderDate(row));
  const now = new Date();
  if (periodFilter.value === 'month')
    return (
      d.getMonth() === now.getMonth() && d.getFullYear() === now.getFullYear()
    );
  if (periodFilter.value === 'quarter')
    return (
      d.getFullYear() === now.getFullYear() &&
      Math.floor(d.getMonth() / 3) === Math.floor(now.getMonth() / 3)
    );
  if (periodFilter.value === 'year')
    return d.getFullYear() === now.getFullYear();
  return true;
};
const filtered = computed(() =>
  rows.value.filter(
    row =>
      periodMatch(row) &&
      (statusFilter.value === 'all' || row.status === statusFilter.value) &&
      (ownerFilter.value === 'all' ||
        String(row.owner?.id) === String(ownerFilter.value)) &&
      (customerFilter.value === 'all' ||
        customerName(row) === customerFilter.value) &&
      (!search.value ||
        `${row.order_number} ${customerName(row)} ${row.deal?.title || ''} ${row.proposal?.proposal_number || ''}`
          .toLowerCase()
          .includes(search.value.toLowerCase()))
  )
);
const pagedRows = computed(() =>
  filtered.value.slice(
    (page.value - 1) * perPage.value,
    page.value * perPage.value
  )
);
const pageCount = computed(() =>
  Math.max(1, Math.ceil(filtered.value.length / perPage.value))
);
watch(
  [search, statusFilter, ownerFilter, customerFilter, periodFilter, perPage],
  () => {
    page.value = 1;
  }
);
watch(pageCount, count => {
  page.value = Math.min(page.value, count);
});
const kpiRows = computed(() => filtered.value);
const previousPeriodRows = computed(() => {
  if (periodFilter.value === 'all') return [];
  const now = new Date();
  let start;
  let end;
  if (periodFilter.value === 'month') {
    start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    end = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
  } else if (periodFilter.value === 'quarter') {
    const currentQuarter = Math.floor(now.getMonth() / 3);
    start = new Date(now.getFullYear(), (currentQuarter - 1) * 3, 1);
    end = new Date(now.getFullYear(), currentQuarter * 3, 0, 23, 59, 59);
  } else {
    start = new Date(now.getFullYear() - 1, 0, 1);
    end = new Date(now.getFullYear() - 1, 11, 31, 23, 59, 59);
  }
  return rows.value.filter(row => {
    const d = new Date(orderDate(row));
    return (
      d >= start &&
      d <= end &&
      (statusFilter.value === 'all' || row.status === statusFilter.value) &&
      (ownerFilter.value === 'all' ||
        String(row.owner?.id) === String(ownerFilter.value)) &&
      (customerFilter.value === 'all' ||
        customerName(row) === customerFilter.value) &&
      (!search.value ||
        `${row.order_number} ${customerName(row)} ${row.deal?.title || ''} ${row.proposal?.proposal_number || ''}`
          .toLowerCase()
          .includes(search.value.toLowerCase()))
    );
  });
});
const totals = computed(() => {
  const rs = kpiRows.value;
  const live = rs.filter(active);
  const total = live.reduce(
    (sum, row) => sum + Number(row.total_cents || 0),
    0
  );
  const mrr = live.reduce(
    (sum, row) => sum + Number(row.monthly_cents || 0),
    0
  );
  return {
    count: rs.length,
    total,
    mrr,
    approval: rs.filter(r => r.status === 'pending').length,
    implementation: rs.filter(r =>
      ['approved', 'separating', 'invoiced', 'shipped'].includes(r.status)
    ).length,
    active: rs.filter(r => r.status === 'completed').length,
    ticket: live.length ? Math.round(total / live.length) : 0,
    conversion: rs.length
      ? Math.round(
          (rs.filter(r =>
            [
              'approved',
              'separating',
              'invoiced',
              'shipped',
              'completed',
            ].includes(r.status)
          ).length /
            rs.length) *
            100
        )
      : 0,
  };
});
const statusCounts = computed(() =>
  [
    'draft',
    'pending',
    'approved',
    'separating',
    'invoiced',
    'shipped',
    'completed',
    'canceled',
  ].map(status => ({
    status,
    count: kpiRows.value.filter(r => r.status === status).length,
  }))
);
const previousTotals = computed(() => {
  const live = previousPeriodRows.value.filter(active);
  return {
    total: live.reduce((sum, row) => sum + Number(row.total_cents || 0), 0),
    count: previousPeriodRows.value.length,
  };
});
const salesDelta = computed(() =>
  previousTotals.value.total
    ? Math.round(
        ((totals.value.total - previousTotals.value.total) /
          previousTotals.value.total) *
          100
      )
    : null
);
const countDelta = computed(() =>
  previousTotals.value.count
    ? Math.round(
        ((totals.value.count - previousTotals.value.count) /
          previousTotals.value.count) *
          100
      )
    : null
);
const statusDonut = computed(() => {
  const palette = [
    '#94a3b8',
    '#f59e0b',
    '#22c55e',
    '#3b82f6',
    '#8b5cf6',
    '#06b6d4',
    '#10b981',
    '#ef4444',
  ];
  const total = Math.max(
    1,
    statusCounts.value.reduce((sum, item) => sum + item.count, 0)
  );
  let cursor = 0;
  const stops = statusCounts.value.map((item, index) => {
    const start = cursor;
    cursor += (item.count / total) * 100;
    return `${palette[index]} ${start}% ${cursor}%`;
  });
  return { background: `conic-gradient(${stops.join(',')})` };
});
const latest = computed(() =>
  [...rows.value]
    .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
    .slice(0, 4)
);
const upcoming = computed(() =>
  rows.value
    .filter(
      r =>
        r.snapshot?.activation_date &&
        !['completed', 'canceled'].includes(r.status)
    )
    .sort((a, b) =>
      String(a.snapshot.activation_date).localeCompare(
        String(b.snapshot.activation_date)
      )
    )
    .slice(0, 4)
);

const detailLoading = ref(false);
const open = async row => {
  editingItems.value = false;
  selected.value = row;
  detailLoading.value = true;
  router.replace({ query: { ...route.query, orderId: row.id } });
  try {
    const { data } = await salesOrdersAPI.show(row.id);
    if (String(selected.value?.id) === String(row.id)) selected.value = data;
  } catch (e) {
    useAlert('Não foi possível carregar o detalhe do pedido.');
  } finally {
    detailLoading.value = false;
  }
};
const load = async () => {
  loading.value = true;
  try {
    const response = await salesOrdersAPI.list();
    rows.value = response.data || [];
    const q = route.query.orderId;
    if (q) {
      const row = rows.value.find(x => String(x.id) === String(q));
      if (row) await open(row);
    }
  } finally {
    loading.value = false;
  }
};
const close = () => {
  selected.value = null;
  const q = { ...route.query };
  delete q.orderId;
  router.replace({ query: q });
};
const changeStatus = async status => {
  if (!selected.value) return;
  saving.value = true;
  try {
    const { data } = await salesOrdersAPI.update(selected.value.id, {
      sales_order: { status },
    });
    selected.value = data;
    await load();
    useAlert('Status do pedido atualizado.');
  } catch (e) {
    useAlert(
      e.response?.data?.errors?.join(', ') ||
        'Não foi possível atualizar o pedido.'
    );
  } finally {
    saving.value = false;
  }
};
const startItemEdit = () => {
  draftItems.value = selected.value.items.map(item => ({ ...item }));
  editingItems.value = true;
};
const recalculateItem = item => {
  item.one_time_cents = Math.max(
    Math.round(Number(item.unit_cents || 0) * Number(item.quantity || 1)) -
      Number(item.discount_cents || 0),
    0
  );
};
const saveItems = async () => {
  if (!selected.value) return;
  saving.value = true;
  try {
    const { data } = await salesOrdersAPI.update(selected.value.id, {
      sales_order: { items: draftItems.value },
    });
    selected.value = data;
    editingItems.value = false;
    await load();
    useAlert('Itens e indicadores recalculados.');
  } catch (e) {
    useAlert(
      e.response?.data?.errors?.join(', ') ||
        'Não foi possível atualizar os itens.'
    );
  } finally {
    saving.value = false;
  }
};
const newContract = () =>
  router.push({
    name: 'crm_contract_new',
    params: { accountId: route.params.accountId },
    query: { orderId: selected.value.id },
  });
const downloadPdf = async (row, event) => {
  event?.stopPropagation();
  try {
    const { data } = await salesOrdersAPI.pdf(row.id);
    const url = URL.createObjectURL(data);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${row.order_number}.pdf`;
    a.click();
    URL.revokeObjectURL(url);
  } catch (e) {
    useAlert('Não foi possível gerar o PDF do pedido.');
  }
};
const clearFilters = () => {
  periodFilter.value = 'all';
  statusFilter.value = 'all';
  ownerFilter.value = 'all';
  customerFilter.value = 'all';
  search.value = '';
  page.value = 1;
};
const exportCsv = () => {
  const header = [
    'Pedido',
    'Cliente',
    'Negócio',
    'Proposta',
    'Responsável',
    'Valor',
    'MRR',
    'Data',
    'Status',
  ];
  const body = filtered.value.map(r => [
    r.order_number,
    customerName(r),
    r.deal?.title || '',
    r.proposal?.proposal_number || '',
    r.owner?.name || '',
    (Number(r.total_cents || 0) / 100).toFixed(2),
    (Number(r.monthly_cents || 0) / 100).toFixed(2),
    dateLabel(orderDate(r)),
    statusLabel(r.status),
  ]);
  const csv = [header, ...body]
    .map(line =>
      line.map(v => `"${String(v).replaceAll('"', '""')}"`).join(';')
    )
    .join('\n');
  const blob = new Blob([`\ufeff${csv}`], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'vendas-pedidos.csv';
  a.click();
  URL.revokeObjectURL(url);
};
const newOrder = () =>
  router.push({
    name: 'crm_order_new',
    params: { accountId: route.params.accountId },
  });
const allOnPageSelected = computed(
  () =>
    pagedRows.value.length > 0 &&
    pagedRows.value.every(r => selectedIds.value.includes(r.id))
);
const togglePage = () => {
  if (allOnPageSelected.value)
    selectedIds.value = selectedIds.value.filter(
      id => !pagedRows.value.some(r => r.id === id)
    );
  else
    selectedIds.value = [
      ...new Set([...selectedIds.value, ...pagedRows.value.map(r => r.id)]),
    ];
};
onMounted(load);
</script>

<template>
  <div
    class="h-full overflow-auto bg-n-background dark:bg-n-background p-4 sm:p-6"
  >
    <header class="mb-5 flex flex-wrap items-center justify-between gap-4">
      <div class="flex items-center gap-3">
        <span
          class="grid size-12 place-content-center rounded-2xl bg-blue-600 text-white shadow-lg shadow-blue-100"
          ><i class="i-lucide-shopping-cart size-6"
        /></span>
        <div>
          <h2 class="text-2xl font-bold text-n-slate-12">Vendas / Pedidos</h2>
          <p class="text-sm text-n-slate-11">
            Gerencie os pedidos, acompanhe o faturamento e o progresso das
            implantações.
          </p>
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <button
          class="rounded-xl border bg-n-solid-2 px-4 py-2.5 font-semibold"
          @click="exportCsv"
        >
          <i class="i-lucide-download mr-2 inline size-4" />Exportar</button
        ><button
          class="rounded-xl border bg-n-solid-2 px-4 py-2.5 font-semibold"
          :disabled="loading"
          @click="load"
        >
          Atualizar</button
        ><button
          class="rounded-xl bg-blue-600 px-5 py-2.5 font-semibold text-white shadow-lg shadow-blue-100"
          @click="newOrder"
        >
          + Novo pedido
        </button>
      </div>
    </header>

    <section class="mb-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
      <article
        v-for="card in [
          [
            'Vendas no período',
            money(totals.total),
            `${totals.count} pedidos`,
            'i-lucide-shopping-cart',
          ],
          [
            'Receita vendida',
            money(totals.total),
            'Valor contratado',
            'i-lucide-circle-dollar-sign',
          ],
          [
            'MRR vendido',
            money(totals.mrr),
            'Receita recorrente mensal',
            'i-lucide-chart-no-axes-combined',
          ],
          [
            'Aguardando aprovação',
            totals.approval,
            'Pedidos pendentes',
            'i-lucide-clock-3',
          ],
          [
            'Em implantação',
            totals.implementation,
            'Operação em andamento',
            'i-lucide-settings',
          ],
          [
            'Ativas',
            totals.active,
            'Pedidos concluídos',
            'i-lucide-circle-check-big',
          ],
        ]"
        :key="card[0]"
        class="rounded-2xl border border-slate-200 bg-n-solid-2 p-4 shadow-sm"
      >
        <div class="mb-3 flex items-start justify-between">
          <p class="text-xs font-medium text-n-slate-11">{{ card[0] }}</p>
          <span
            class="grid size-9 place-content-center rounded-xl bg-blue-50 text-blue-600"
          >
            <i class="size-4" :class="card[3]" />
          </span>
        </div>
        <strong class="block text-xl text-n-slate-12">{{ card[1] }}</strong
        ><small class="text-n-slate-11">{{ card[2] }}</small>
      </article>
    </section>

    <section class="mb-5 grid gap-4 xl:grid-cols-[360px_minmax(0,1fr)]">
      <article
        class="rounded-2xl border border-slate-200 bg-n-solid-2 p-5 shadow-sm"
      >
        <div class="flex items-start justify-between">
          <div>
            <h3 class="font-bold text-n-slate-12">Pedidos por status</h3>
            <p class="text-xs text-n-slate-11">
              Distribuição do período e filtros atuais.
            </p>
          </div>
          <span
            class="rounded-full bg-blue-50 px-2.5 py-1 text-xs font-semibold text-blue-700"
            >{{ totals.count }} pedidos</span
          >
        </div>
        <div class="mt-5 flex items-center gap-5">
          <div
            class="relative size-36 shrink-0 rounded-full"
            :style="statusDonut"
          >
            <div
              class="absolute inset-5 grid place-content-center rounded-full bg-n-solid-2 text-center"
            >
              <strong class="text-2xl text-n-slate-12">{{
                totals.count
              }}</strong>
              <span class="text-[11px] text-n-slate-11">total</span>
            </div>
          </div>
          <div class="grid flex-1 grid-cols-2 gap-x-3 gap-y-2 text-xs">
            <div
              v-for="item in statusCounts"
              :key="item.status"
              class="flex items-center justify-between gap-2"
            >
              <span class="truncate text-n-slate-11">{{
                statusLabel(item.status)
              }}</span>
              <b class="text-n-slate-12">{{ item.count }}</b>
            </div>
          </div>
        </div>
      </article>
      <article
        class="rounded-2xl border border-slate-200 bg-n-solid-2 p-5 shadow-sm"
      >
        <div class="flex items-center justify-between">
          <div>
            <h3 class="font-bold text-n-slate-12">
              Comparativo com período anterior
            </h3>
            <p class="text-xs text-n-slate-11">
              Os KPIs respeitam período, cliente, responsável, status e busca.
            </p>
          </div>
          <i class="i-lucide-chart-no-axes-combined size-5 text-blue-600" />
        </div>
        <div class="mt-5 grid gap-3 sm:grid-cols-3">
          <div class="rounded-xl bg-blue-50 p-4">
            <p class="text-xs text-blue-700">Receita atual</p>
            <strong class="mt-1 block text-xl text-n-slate-12">{{
              money(totals.total)
            }}</strong>
            <span
              v-if="salesDelta !== null"
              class="mt-2 inline-flex rounded-full px-2 py-1 text-xs font-semibold"
              :class="
                salesDelta >= 0
                  ? 'bg-emerald-100 text-emerald-700'
                  : 'bg-red-100 text-red-700'
              "
              >{{ salesDelta >= 0 ? '+' : '' }}{{ salesDelta }}%</span
            >
            <span v-else class="mt-2 block text-xs text-n-slate-11">
              Sem base anterior
            </span>
          </div>
          <div class="rounded-xl bg-violet-50 p-4">
            <p class="text-xs text-violet-700">Pedidos atuais</p>
            <strong class="mt-1 block text-xl text-n-slate-12">{{
              totals.count
            }}</strong>
            <span
              v-if="countDelta !== null"
              class="mt-2 inline-flex rounded-full px-2 py-1 text-xs font-semibold"
              :class="
                countDelta >= 0
                  ? 'bg-emerald-100 text-emerald-700'
                  : 'bg-red-100 text-red-700'
              "
              >{{ countDelta >= 0 ? '+' : '' }}{{ countDelta }}%</span
            >
            <span v-else class="mt-2 block text-xs text-n-slate-11">
              Sem base anterior
            </span>
          </div>
          <div class="rounded-xl bg-emerald-50 p-4">
            <p class="text-xs text-emerald-700">Conversão</p>
            <strong class="mt-1 block text-xl text-n-slate-12"
              >{{ totals.conversion }}%</strong
            >
            <p class="mt-2 text-xs text-n-slate-11">
              Base filtrada em tempo real
            </p>
          </div>
        </div>
      </article>
    </section>

    <section
      class="mb-4 grid gap-3 rounded-2xl border border-slate-200 bg-n-solid-2 p-4 shadow-sm md:grid-cols-2 xl:grid-cols-[180px_180px_220px_220px_1fr_auto]"
    >
      <select
        v-model="periodFilter"
        class="rounded-xl border border-slate-200 px-3 py-2.5"
      >
        <option value="all">Todos os períodos</option>
        <option value="month">Este mês</option>
        <option value="quarter">Este trimestre</option>
        <option value="year">Este ano</option>
      </select>
      <select
        v-model="statusFilter"
        class="rounded-xl border border-slate-200 px-3 py-2.5"
      >
        <option value="all">Todos os status</option>
        <option v-for="s in statusCounts" :key="s.status" :value="s.status">
          {{ statusLabel(s.status) }}
        </option>
      </select>
      <select
        v-model="ownerFilter"
        class="rounded-xl border border-slate-200 px-3 py-2.5"
      >
        <option value="all">Todos os responsáveis</option>
        <option v-for="o in owners" :key="o.id" :value="o.id">
          {{ o.name }}
        </option>
      </select>
      <select
        v-model="customerFilter"
        class="rounded-xl border border-slate-200 px-3 py-2.5"
      >
        <option value="all">Todos os clientes</option>
        <option v-for="c in customers" :key="c" :value="c">{{ c }}</option>
      </select>
      <div class="relative">
        <i
          class="i-lucide-search absolute left-3 top-3 size-4 text-n-slate-11"
        /><input
          v-model="search"
          class="w-full rounded-xl border border-slate-200 py-2.5 pl-10 pr-3"
          placeholder="Buscar por número, cliente ou negócio..."
        />
      </div>
      <button
        class="rounded-xl border border-slate-200 px-4 py-2.5"
        @click="clearFilters"
      >
        <i class="i-lucide-filter-x mr-2 inline size-4" />Limpar filtros
      </button>
    </section>

    <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_290px]">
      <div class="min-w-0 space-y-4">
        <section
          class="overflow-hidden rounded-2xl border border-slate-200 bg-n-solid-2 shadow-sm"
        >
          <div
            class="flex flex-wrap items-center justify-between gap-3 border-b p-4"
          >
            <div>
              <h3 class="font-bold text-n-slate-12">Pedidos</h3>
              <p class="text-xs text-n-slate-11">
                Lista de pedidos gerados no CRM.
              </p>
            </div>
            <div class="flex rounded-xl bg-n-slate-3 p-1">
              <button
                class="rounded-lg px-3 py-1.5 text-sm"
                :class="
                  view === 'list'
                    ? 'bg-blue-600 text-white shadow'
                    : 'text-n-slate-11'
                "
                @click="view = 'list'"
              >
                ☷ Lista</button
              ><button
                class="rounded-lg px-3 py-1.5 text-sm"
                :class="
                  view === 'kanban'
                    ? 'bg-blue-600 text-white shadow'
                    : 'text-n-slate-11'
                "
                @click="view = 'kanban'"
              >
                ▥ Kanban
              </button>
            </div>
          </div>
          <div v-if="view === 'list'" class="overflow-x-auto">
            <table class="w-full min-w-[1050px] text-sm">
              <thead
                class="bg-n-slate-2 text-left text-[11px] uppercase text-n-slate-11"
              >
                <tr>
                  <th class="p-3">
                    <input
                      type="checkbox"
                      :checked="allOnPageSelected"
                      @change="togglePage"
                    />
                  </th>
                  <th class="p-3">Nº do pedido</th>
                  <th class="p-3">Cliente</th>
                  <th class="p-3">Negócio</th>
                  <th class="p-3">Proposta</th>
                  <th class="p-3">Responsável</th>
                  <th class="p-3">Valor</th>
                  <th class="p-3">MRR</th>
                  <th class="p-3">Data</th>
                  <th class="p-3">Status</th>
                  <th class="p-3">Ações</th>
                </tr>
              </thead>
              <tbody class="divide-y">
                <tr v-if="loading">
                  <td colspan="11" class="p-10 text-center">Carregando…</td>
                </tr>
                <tr
                  v-for="row in pagedRows"
                  :key="row.id"
                  class="cursor-pointer hover:bg-blue-50/40"
                  @click="open(row)"
                >
                  <td class="p-3" @click.stop>
                    <input
                      v-model="selectedIds"
                      type="checkbox"
                      :value="row.id"
                    />
                  </td>
                  <td class="p-3 font-semibold text-blue-700">
                    <button
                      type="button"
                      class="underline underline-offset-2"
                      @click.stop="open(row)"
                    >
                      {{ row.order_number }}
                    </button>
                  </td>
                  <td class="p-3">
                    <b>{{ customerName(row) }}</b>
                    <p class="text-xs text-n-slate-11">
                      {{ row.contact?.email || '' }}
                    </p>
                  </td>
                  <td class="p-3">{{ row.deal?.title || 'Pedido direto' }}</td>
                  <td class="p-3 text-blue-600">
                    {{ row.proposal?.proposal_number || '—' }}
                  </td>
                  <td class="p-3">{{ row.owner?.name || '—' }}</td>
                  <td class="p-3 font-semibold">
                    {{ money(row.total_cents) }}
                  </td>
                  <td class="p-3">{{ money(row.monthly_cents) }}</td>
                  <td class="p-3">{{ dateLabel(orderDate(row)) }}</td>
                  <td class="p-3">
                    <span
                      class="rounded-full px-2.5 py-1 text-xs font-semibold"
                      :class="statusTone(row.status)"
                      >{{ statusLabel(row.status) }}</span
                    >
                  </td>
                  <td class="p-3">
                    <button
                      type="button"
                      class="mr-2 rounded-lg border p-2"
                      title="Ver pedido"
                      aria-label="Ver pedido"
                      @click.stop="open(row)"
                    >
                      <i class="i-lucide-file-text size-4" />
                    </button>
                    <button
                      title="Baixar PDF"
                      aria-label="Baixar PDF"
                      class="rounded-lg border p-2"
                      @click.stop="downloadPdf(row, $event)"
                    >
                      <i class="i-lucide-file-down size-4" />
                    </button>
                  </td>
                </tr>
                <tr v-if="!loading && !pagedRows.length">
                  <td colspan="11" class="p-10 text-center text-n-slate-11">
                    Nenhum pedido encontrado.
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div
            v-else
            class="grid min-w-[1000px] grid-cols-4 gap-3 overflow-x-auto bg-n-slate-2 p-4"
          >
            <section
              v-for="st in ['pending', 'approved', 'separating', 'completed']"
              :key="st"
              class="rounded-2xl bg-n-slate-3 p-3"
            >
              <h3 class="mb-3 font-bold">
                {{ statusLabel(st) }}
                <span class="float-right text-xs text-n-slate-11">{{
                  filtered.filter(r => r.status === st).length
                }}</span>
              </h3>
              <article
                v-for="row in filtered.filter(r => r.status === st)"
                :key="row.id"
                class="mb-2 cursor-pointer rounded-xl border bg-n-solid-2 p-3 shadow-sm"
                @click="open(row)"
              >
                <b class="text-blue-700">{{ row.order_number }}</b>
                <p class="text-sm">{{ customerName(row) }}</p>
                <p class="mt-2 font-semibold">{{ money(row.total_cents) }}</p>
              </article>
            </section>
          </div>
          <footer
            v-if="view === 'list'"
            class="flex flex-wrap items-center justify-between gap-3 border-t p-4 text-sm text-n-slate-11"
          >
            <span
              >Mostrando {{ filtered.length ? (page - 1) * perPage + 1 : 0 }} a
              {{ Math.min(page * perPage, filtered.length) }} de
              {{ filtered.length }} pedidos</span
            >
            <div class="flex items-center gap-2">
              <button
                class="rounded-lg border px-3 py-1.5"
                :disabled="page <= 1"
                @click="page--"
              >
                ‹</button
              ><button
                v-for="p in pageCount"
                :key="p"
                class="size-8 rounded-lg border"
                :class="p === page && 'bg-blue-600 text-white'"
                @click="page = p"
              >
                {{ p }}</button
              ><button
                class="rounded-lg border px-3 py-1.5"
                :disabled="page >= pageCount"
                @click="page++"
              >
                ›</button
              ><select v-model="perPage" class="rounded-lg border px-2 py-1.5">
                <option :value="10">10 por página</option>
                <option :value="20">20 por página</option>
                <option :value="50">50 por página</option>
              </select>
            </div>
          </footer>
        </section>

        <div class="grid gap-4 lg:grid-cols-2">
          <section class="rounded-2xl border bg-n-solid-2 p-4 shadow-sm">
            <div class="mb-3 flex items-center justify-between">
              <h3 class="font-bold">Últimos pedidos criados</h3>
              <span class="text-xs text-blue-600">Atualizado pelo CRM</span>
            </div>
            <div
              v-for="row in latest"
              :key="row.id"
              class="flex cursor-pointer items-center justify-between border-t py-3 text-sm"
              @click="open(row)"
            >
              <div>
                <b class="text-blue-600">{{ row.order_number }}</b
                ><span class="ml-3">{{ customerName(row) }}</span>
              </div>
              <span
                class="rounded-full px-2 py-1 text-xs"
                :class="statusTone(row.status)"
                >{{ statusLabel(row.status) }}</span
              >
            </div>
            <p
              v-if="!latest.length"
              class="py-6 text-center text-sm text-n-slate-11"
            >
              Nenhum pedido criado.
            </p>
          </section>
          <section class="rounded-2xl border bg-n-solid-2 p-4 shadow-sm">
            <div class="mb-3 flex items-center justify-between">
              <h3 class="font-bold">Próximas implantações</h3>
              <span class="text-xs text-blue-600">Previsão de ativação</span>
            </div>
            <div
              v-for="row in upcoming"
              :key="row.id"
              class="flex cursor-pointer items-center justify-between border-t py-3 text-sm"
              @click="open(row)"
            >
              <div>
                <b>{{ customerName(row) }}</b>
                <p class="text-xs text-n-slate-11">{{ row.order_number }}</p>
              </div>
              <div class="text-right">
                <b>{{ dateLabel(row.snapshot.activation_date) }}</b>
                <p class="text-xs text-blue-600">
                  {{ statusLabel(row.status) }}
                </p>
              </div>
            </div>
            <p
              v-if="!upcoming.length"
              class="py-6 text-center text-sm text-n-slate-11"
            >
              Nenhuma implantação programada.
            </p>
          </section>
        </div>
      </div>

      <aside class="space-y-4">
        <section class="rounded-2xl border bg-n-solid-2 p-4 shadow-sm">
          <h3 class="font-bold">Resumo do período</h3>
          <div class="mt-3 space-y-2 text-sm">
            <p class="flex justify-between">
              <span>Pedidos</span><b>{{ totals.count }}</b>
            </p>
            <p class="flex justify-between">
              <span>Valor único</span><b>{{ money(totals.total) }}</b>
            </p>
            <p class="flex justify-between">
              <span>MRR</span><b>{{ money(totals.mrr) }}</b>
            </p>
            <p class="flex justify-between">
              <span>Ticket médio</span><b>{{ money(totals.ticket) }}</b>
            </p>
            <p class="flex justify-between">
              <span>Taxa de conversão</span><b>{{ totals.conversion }}%</b>
            </p>
          </div>
        </section>
        <section class="rounded-2xl border bg-n-solid-2 p-4 shadow-sm">
          <h3 class="font-bold">Pedidos por status</h3>
          <div class="mt-4 space-y-2">
            <div
              v-for="s in statusCounts"
              :key="s.status"
              class="flex items-center justify-between text-sm"
            >
              <span class="flex items-center gap-2"
                ><i class="size-2 rounded-full bg-blue-500" />{{
                  statusLabel(s.status)
                }}</span
              ><b>{{ s.count }}</b>
            </div>
          </div>
        </section>
        <section class="rounded-2xl border bg-n-solid-2 p-4 shadow-sm">
          <h3 class="font-bold">Ações rápidas</h3>
          <div class="mt-3 grid gap-2">
            <button
              class="rounded-xl border px-3 py-2 text-left text-sm hover:bg-n-slate-2"
              @click="newOrder"
            >
              ＋ Novo pedido</button
            ><button
              class="rounded-xl border px-3 py-2 text-left text-sm"
              @click="
                router.push({
                  name: 'crm_proposals',
                  params: { accountId: route.params.accountId },
                })
              "
            >
              ⇩ Importar de proposta</button
            ><button
              class="rounded-xl border px-3 py-2 text-left text-sm"
              @click="
                router.push({
                  name: 'crm_indicators',
                  params: { accountId: route.params.accountId },
                })
              "
            >
              ▥ Relatório de vendas</button
            ><button
              class="rounded-xl border px-3 py-2 text-left text-sm"
              @click="statusFilter = 'separating'"
            >
              ⚙ Pedidos em implantação</button
            ><button
              class="rounded-xl border px-3 py-2 text-left text-sm"
              @click="statusFilter = 'invoiced'"
            >
              ▤ Faturas geradas
            </button>
          </div>
        </section>
      </aside>
    </div>

    <Teleport to="body">
      <div
        v-if="selected"
        :class="crmControlClasses"
        class="fixed inset-0 z-[90] flex justify-end bg-black/40"
        @click.self="close"
      >
        <aside
          class="h-full w-full max-w-2xl overflow-auto bg-n-solid-2 p-6 shadow-2xl"
        >
          <div class="flex justify-between">
            <div>
              <p class="text-xs uppercase text-n-slate-11">
                Visão geral do pedido
              </p>
              <h3 class="text-xl font-bold">{{ selected.order_number }}</h3>
              <p class="text-sm text-n-slate-11">
                {{ customerName(selected) }}
              </p>
            </div>
            <button class="i-lucide-x size-5" title="Fechar" @click="close" />
          </div>
          <p v-if="detailLoading" class="mt-3 text-sm" role="status">
            Carregando detalhe…
          </p>
          <div class="mt-5 flex gap-2">
            <button
              class="rounded-lg border border-red-200 px-3 py-2 text-red-700"
              @click="downloadPdf(selected)"
            >
              Gerar PDF</button
            ><button class="rounded-lg border px-3 py-2" @click="newContract">
              Gerar contrato
            </button>
          </div>
          <div
            class="mt-6 grid grid-cols-2 gap-3 rounded-xl border p-4 text-sm"
          >
            <div>
              <span class="text-xs text-n-slate-11">Total</span
              ><strong class="block text-lg">{{
                money(selected.total_cents)
              }}</strong>
            </div>
            <div>
              <span class="text-xs text-n-slate-11">MRR</span
              ><strong class="block"
                >{{ money(selected.monthly_cents) }}/mês</strong
              >
            </div>
            <div>
              <span class="text-xs text-n-slate-11">Origem</span
              ><strong class="block">{{
                originLabel(selected.order_origin)
              }}</strong>
            </div>
            <div>
              <span class="text-xs text-n-slate-11">Proposta</span
              ><strong class="block">{{
                selected.proposal
                  ? `${selected.proposal.proposal_number} v${selected.proposal.version_number || selected.proposal_version || 1}`
                  : 'Sem proposta'
              }}</strong>
            </div>
            <div>
              <span class="text-xs text-n-slate-11">Criado por</span
              ><strong class="block">{{
                selected.created_by?.name || selected.owner?.name || '—'
              }}</strong>
            </div>
            <div>
              <span class="text-xs text-n-slate-11">Ativação</span
              ><strong class="block">{{
                dateLabel(selected.snapshot?.activation_date)
              }}</strong>
            </div>
          </div>
          <section
            class="mt-4 grid grid-cols-2 gap-3 rounded-xl border p-4 text-sm"
          >
            <div>
              <span>Empresa</span
              ><strong class="block">{{
                selected.company?.name || '—'
              }}</strong>
            </div>
            <div>
              <span>Negócio</span
              ><strong class="block">{{
                selected.deal?.title || 'Pedido direto'
              }}</strong>
            </div>
            <div>
              <span>Responsável</span
              ><strong class="block">{{ selected.owner?.name || '—' }}</strong>
            </div>
            <div>
              <span>Contato</span
              ><strong class="block">{{
                selected.contact?.email || selected.contact?.phone_number || '—'
              }}</strong>
            </div>
            <div>
              <span>Condição de pagamento</span
              ><strong class="block">{{
                selected.payment_condition || '—'
              }}</strong>
            </div>
            <div>
              <span>Forma de pagamento</span
              ><strong class="block">{{
                selected.payment_method || '—'
              }}</strong>
            </div>
            <div>
              <span>Entrada</span
              ><strong class="block">{{
                money(selected.down_payment_cents)
              }}</strong>
            </div>
            <div>
              <span>Parcelas</span
              ><strong class="block">{{
                selected.installments_count || '—'
              }}</strong>
            </div>
            <div>
              <span>Criado em</span
              ><strong class="block">{{
                dateLabel(selected.created_at)
              }}</strong>
            </div>
            <div>
              <span>Atualizado em</span
              ><strong class="block">{{
                dateLabel(selected.updated_at)
              }}</strong>
            </div>
            <div class="col-span-2">
              <span>Implantação / observações</span>
              <p>
                {{
                  selected.snapshot?.operation_notes || selected.notes || '—'
                }}
              </p>
            </div>
          </section>
          <section class="mt-4 rounded-xl border p-4">
            <div class="flex items-center justify-between">
              <h4 class="font-semibold">Itens</h4>
              <button
                v-if="!editingItems"
                class="rounded-lg border px-3 py-1.5 text-sm"
                @click="startItemEdit"
              >
                Editar itens
              </button>
            </div>
            <template v-if="editingItems">
              <div
                v-for="item in draftItems"
                :key="item.id"
                class="mt-3 grid grid-cols-2 gap-2 rounded-lg border p-3 text-sm md:grid-cols-5"
              >
                <label class="col-span-2"
                  >Item<input
                    v-model="item.name"
                    class="mt-1 w-full rounded-lg border p-2" /></label
                ><label
                  >Quantidade<input
                    v-model.number="item.quantity"
                    type="number"
                    min="0.001"
                    step="0.001"
                    class="mt-1 w-full rounded-lg border p-2"
                    @change="recalculateItem(item)" /></label
                ><label
                  >Valor unitário<input
                    v-model.number="item.unit_cents"
                    type="number"
                    min="0"
                    class="mt-1 w-full rounded-lg border p-2"
                    @change="recalculateItem(item)" /></label
                ><label
                  >Desconto<input
                    v-model.number="item.discount_cents"
                    type="number"
                    min="0"
                    class="mt-1 w-full rounded-lg border p-2"
                    @change="recalculateItem(item)" /></label
                ><label
                  >Valor líquido<input
                    v-model.number="item.one_time_cents"
                    type="number"
                    min="0"
                    class="mt-1 w-full rounded-lg border p-2" /></label
                ><label
                  >MRR<input
                    v-model.number="item.recurring_cents"
                    type="number"
                    min="0"
                    class="mt-1 w-full rounded-lg border p-2"
                /></label>
              </div>
              <div class="mt-3 flex justify-end gap-2">
                <button
                  class="rounded-lg border px-3 py-2"
                  :disabled="saving"
                  @click="editingItems = false"
                >
                  Cancelar</button
                ><button
                  class="rounded-lg bg-blue-600 px-3 py-2 font-semibold text-white"
                  :disabled="saving"
                  @click="saveItems"
                >
                  Salvar e recalcular
                </button>
              </div> </template
            ><template v-else>
              <div
                v-for="i in selected.items"
                :key="i.id"
                class="flex justify-between border-t py-2 text-sm"
              >
                <span>{{ i.name }} × {{ i.quantity }}</span
                ><span
                  ><b>{{ money(i.one_time_cents) }}</b> · MRR
                  {{ money(i.recurring_cents) }}</span
                >
              </div>
            </template>
          </section>
          <section class="mt-4 rounded-xl border p-4">
            <h4 class="font-semibold">Fluxo do pedido</h4>
            <p class="mt-2 text-sm">
              Pendente → Aprovado → Em implantação → Faturado → Em entrega →
              Ativo
            </p>
            <p class="mt-2 font-semibold">{{ statusLabel(selected.status) }}</p>
            <div class="mt-3 flex gap-2">
              <button
                v-for="status in selected.allowed_statuses || []"
                :key="status"
                class="rounded-lg border px-3 py-2"
                :disabled="saving || detailLoading"
                @click="changeStatus(status)"
              >
                {{
                  status === 'canceled'
                    ? 'Cancelar pedido'
                    : statusLabel(status)
                }}
              </button>
            </div>
          </section>
          <section class="mt-4 rounded-xl border p-4">
            <h4 class="font-semibold">Histórico / timeline</h4>
            <ol class="mt-3 space-y-3">
              <li
                v-for="event in selected.history || []"
                :key="event.id"
                class="border-l-2 pl-3 text-sm"
              >
                <strong>{{ event.event_type }}</strong>
                <p>{{ new Date(event.created_at).toLocaleString('pt-BR') }}</p>
                <p v-if="event.metadata?.before?.status">
                  {{ statusLabel(event.metadata.before.status) }} →
                  {{ statusLabel(event.metadata.after?.status) }}
                </p>
              </li>
            </ol>
            <p v-if="!selected.history?.length" class="mt-2 text-sm">
              Nenhum evento registrado.
            </p>
          </section>
        </aside>
      </div>
    </Teleport>
  </div>
</template>
