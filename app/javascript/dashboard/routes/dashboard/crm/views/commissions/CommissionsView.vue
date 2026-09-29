<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import AgentsAPI from 'dashboard/api/agents';
import TeamsAPI from 'dashboard/api/teams';
import {
  commissionProgramsAPI,
  commissionsAPI,
  goalsAPI,
} from 'dashboard/api/crm/commercialCycle';
import productsAPI from 'dashboard/api/crm/products';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
const { t } = useI18n();

const route = useRoute();
const router = useRouter();
const store = useStore();
const tabs = [
  ['current', 'Visão atual'],
  ['plans', 'Planos de comissão'],
  ['new', 'Novo plano'],
  ['closing', 'Apuração'],
  ['detail', 'Memória de cálculo'],
  ['approvals', 'Aprovações'],
  ['adjustments', 'Ajustes e estornos'],
  ['payments', 'Pagamentos'],
  ['mine', 'Minha comissão'],
  ['history', 'Histórico'],
];
const planSteps = [
  ['Dados gerais', 'Defina vigência, participantes, tipo e evento gerador.'],
  ['Regras de cálculo', 'Escolha a base comissionável e as regras de apuração.'],
  ['Faixas e metas', 'Configure faixas por venda ou por atingimento e bônus.'],
  ['Produtos e equipes', 'Restrinja produtos, equipes e configure o rateio.'],
  ['Revisão e publicação', 'Revise, simule e publique somente regras válidas.'],
];
const validSections = tabs.map(([key]) => key);
const tab = ref(
  validSections.includes(route.params.section)
    ? route.params.section
    : 'current'
);
const rows = ref([]);
const plans = ref([]);
const products = ref([]);
const agents = ref([]);
const teams = ref([]);
const goals = ref([]);
const planStep = ref(1);
const simulationResult = ref(null);
const sim = reactive({ total:'10000', monthly:'1000', received:'0', margin:'0', attainment:100 });
const summary = ref({});
const selected = ref(null);
const loading = ref(false);
const loadErrors = ref([]);
const reversalReason = ref('');
const saving = ref(false);
const search = ref('');
const statusFilter = ref('all');
const sellerFilter = ref('all');
const programFilter = ref('all');
const page = ref(1);
const perPage = ref(10);
const historyEvents = ref([]);
const editingPlanId = ref(null);
const form = reactive({
  name: '',
  description: '',
  release_condition: 'order_approved',
  starts_on: '',
  ends_on: '',
  active: true,
  plan_type: 'individual',
  base: 'total_cents',
  rate_percent: 5,
  tier_basis: 'sales_value',
  requires_approval: true,
  share_percent: 100,
  product_ids: [],
  user_ids: [],
  team_ids: [],
  goal_ids: [],
  tiers: [{ min_value: '0', max_value: '', min_percent: 0, max_percent: '', rate_percent: 5 }],
  bonuses: [],
});

const money = value =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format((Number(value) || 0) / 100);

const metrics = computed(() => [
  ['Base comissionável', summary.value.commissionable_base_cents || 0],
  ['Comissão prevista', summary.value.forecast_cents || 0],
  ['Em aprovação', summary.value.pending_approval_cents || 0],
  ['Liberada', summary.value.released_cents || 0],
  ['Paga', summary.value.paid_cents || 0],
  ['Estornada', summary.value.reversed_cents || 0],
]);
const currentUserId = computed(() => store.getters.getCurrentUser?.id);
const uniqueSellers = computed(() => [...new Map(rows.value.filter(r=>r.user).map(r=>[r.user.id,r.user])).values()]);
const uniquePrograms = computed(() => [...new Map(rows.value.filter(r=>r.program).map(r=>[r.program.id,r.program])).values()]);
const filteredHistory = computed(() => historyEvents.value.filter(event => {
  const row = rows.value.find(item => Number(item.id) === Number(event.commission_id));
  if (!row) return false;
  return sellerFilter.value === 'all' || String(row.user?.id) === String(sellerFilter.value);
}));
const monthlyEvolution = computed(() => {
  const map = new Map();
  rows.value.forEach(row => {
    const source = row.paid_at || row.released_at || row.updated_at || row.created_at;
    if (!source) return;
    const d = new Date(source);
    const key = `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}`;
    const item = map.get(key) || { key, label: new Intl.DateTimeFormat('pt-BR',{month:'short',year:'2-digit'}).format(d), forecast:0, released:0, paid:0 };
    if (['forecast','pending_approval'].includes(row.status)) item.forecast += Number(row.commission_cents||0);
    if (row.status === 'released') item.released += Number(row.commission_cents||0);
    if (row.status === 'paid') item.paid += Number(row.commission_cents||0);
    map.set(key,item);
  });
  return [...map.values()].sort((a,b)=>a.key.localeCompare(b.key)).slice(-8);
});
const sellerChart = computed(() => uniqueSellers.value.map(seller => ({
  id:seller.id, name:seller.name,
  value:rows.value.filter(r=>r.user?.id===seller.id && r.status!=='reversed').reduce((sum,r)=>sum+Number(r.commission_cents||0),0),
})).sort((a,b)=>b.value-a.value).slice(0,8));
const chartMax = computed(() => Math.max(1,...sellerChart.value.map(i=>i.value),...monthlyEvolution.value.flatMap(i=>[i.forecast,i.released,i.paid])));


const rowsForTab = computed(() => {
  const statuses = {
    closing: ['forecast', 'pending_approval'],
    approvals: ['pending_approval'],
    adjustments: ['forecast', 'pending_approval', 'released', 'paid', 'reversed'],
    payments: ['released', 'paid'],
  };
  let result = statuses[tab.value]
    ? rows.value.filter(row => statuses[tab.value].includes(row.status))
    : rows.value;

  if (tab.value === 'mine') {
    result = result.filter(row => Number(row.user?.id) === Number(currentUserId.value));
  }
  if (statusFilter.value !== 'all') result = result.filter(row => row.status === statusFilter.value);
  if (sellerFilter.value !== 'all') result = result.filter(row => String(row.user?.id) === String(sellerFilter.value));
  if (programFilter.value !== 'all') result = result.filter(row => String(row.program?.id || '') === String(programFilter.value));

  const query = search.value.trim().toLowerCase();
  if (query) {
    result = result.filter(row =>
      [row.order?.order_number, row.user?.name, row.program?.name, row.status]
        .filter(Boolean)
        .some(value => value.toLowerCase().includes(query))
    );
  }
  return result;
});
const pageCount = computed(() => Math.max(1, Math.ceil(rowsForTab.value.length / perPage.value)));
const pagedRows = computed(() => rowsForTab.value.slice((page.value-1)*perPage.value, page.value*perPage.value));

const load = async () => {
  loading.value = true;
  try {
    loadErrors.value = [];
    const sources = [
      ['Comissões', commissionsAPI.list(), rows],
      ['Resumo', commissionsAPI.summary(), summary],
      ['Planos', commissionProgramsAPI.list(), plans],
      ['Produtos', productsAPI.list({ active:true }), products],
      ['Responsáveis', AgentsAPI.get(), agents],
      ['Equipes', TeamsAPI.get(true), teams],
      ['Histórico', commissionsAPI.history(), historyEvents],
      ['Metas', goalsAPI.list(), goals],
    ];
    const responses = await Promise.allSettled(sources.map(([, request]) => request));
    responses.forEach((result,index) => {
      const [label,, target] = sources[index];
      if (result.status === 'fulfilled') target.value = result.value.data;
      else loadErrors.value.push(t('CRM.WORKFLOW_UI.PARTIAL_ERROR', { module:label }));
    });
    if (selected.value) {
      selected.value =
        rows.value.find(item => item.id === selected.value.id) || null;
    }
  } catch (error) {
    useAlert(
      error.response?.data?.message || 'Não foi possível carregar as comissões.'
    );
  } finally {
    loading.value = false;
  }
};

const goTab = value => {
  tab.value = value;
  page.value = 1;
  router.push({
    name: 'crm_commissions',
    params: { accountId: route.params.accountId, section: value },
  });
};

const resetPlan = () => {
  editingPlanId.value = null;
  Object.assign(form, {
    name: '',
    description: '',
    release_condition: 'order_approved',
    starts_on: '',
    ends_on: '',
    active: true,
    plan_type: 'individual',
    base: 'total_cents',
    rate_percent: 5,
    tier_basis: 'sales_value',
    requires_approval: true,
    share_percent: 100,
    product_ids: [],
    user_ids: [],
    team_ids: [],
    goal_ids: [],
    tiers: [{ min_value: '0', max_value: '', min_percent: 0, max_percent: '', rate_percent: 5 }],
    bonuses: [],
  });
  planStep.value = 1;
  simulationResult.value = null;
};

const editPlan = plan => {
  const rules = plan.rules || {};
  editingPlanId.value = plan.id;
  Object.assign(form, {
    name: plan.name,
    description: rules.description || '',
    release_condition: plan.release_condition,
    starts_on: plan.starts_on || '',
    ends_on: plan.ends_on || '',
    active: plan.active,
    plan_type: rules.plan_type || 'individual',
    base: rules.base || 'total_cents',
    rate_percent: Number(rules.rate_percent || 0),
    tier_basis: rules.tier_basis || 'sales_value',
    requires_approval: rules.requires_approval !== false,
    share_percent: Number(rules.share_percent || 100),
    product_ids: rules.product_ids || [],
    user_ids: rules.user_ids || [],
    team_ids: rules.team_ids || [],
    goal_ids: rules.goal_ids || [],
    tiers: rules.tiers?.length
      ? rules.tiers.map(tier => ({
          min_value: tier.min_cents == null ? '0' : String(Number(tier.min_cents) / 100),
          max_value: tier.max_cents == null ? '' : String(Number(tier.max_cents) / 100),
          min_percent: Number(tier.min_percent || 0),
          max_percent: tier.max_percent == null ? '' : Number(tier.max_percent),
          rate_percent: Number(tier.rate_percent || 0),
        }))
      : [{ min_value: '0', max_value: '', min_percent: 0, max_percent: '', rate_percent: 0 }],
    bonuses: (rules.bonuses || []).map(bonus => ({
      attainment_percent: Number(bonus.attainment_percent || 100),
      percent: Number(bonus.percent || 0),
      amount_value: bonus.amount_cents ? String(Number(bonus.amount_cents) / 100) : '',
    })),
  });
  planStep.value = 1;
  simulationResult.value = null;
  goTab('new');
};

const addTier = () => {
  form.tiers.push({
    min_value: '0',
    max_value: '',
    min_percent: 0,
    max_percent: '',
    rate_percent: Number(form.rate_percent || 0),
  });
};

const removeTier = index => {
  form.tiers.splice(index, 1);
  if (!form.tiers.length) addTier();
};

const addBonus = () =>
  form.bonuses.push({
    attainment_percent: 100,
    percent: 0,
    amount_value: '',
  });
const removeBonus = index => form.bonuses.splice(index, 1);

const parseMoneyToCents = value => {
  if (typeof value === 'number') return Math.round(value * 100);
  let raw = String(value ?? '').trim().replace(/[R$\s\u00A0]/g, '');
  if (!raw) return 0;
  if (raw.includes(',') && raw.includes('.')) {
    raw = raw.replace(/\./g, '').replace(',', '.');
  } else if (raw.includes(',')) {
    raw = raw.replace(',', '.');
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? Math.round(parsed * 100) : 0;
};

const buildRules = () => ({
  description: form.description.trim(),
  plan_type: form.plan_type,
  base: form.base,
  rate_percent: Number(form.rate_percent || 0),
  tier_basis: form.tier_basis,
  requires_approval: form.requires_approval,
  share_percent: Number(form.share_percent || 100),
  product_ids: form.product_ids.map(Number),
  user_ids: form.user_ids.map(Number),
  team_ids: form.team_ids.map(Number),
  goal_ids: form.goal_ids.map(Number),
  tiers: form.tiers.map(tier => ({
    min_cents:
      form.tier_basis === 'sales_value'
        ? parseMoneyToCents(tier.min_value)
        : 0,
    max_cents:
      form.tier_basis === 'sales_value' && tier.max_value !== ''
        ? parseMoneyToCents(tier.max_value)
        : null,
    min_percent:
      form.tier_basis === 'goal_attainment'
        ? Number(tier.min_percent || 0)
        : 0,
    max_percent:
      form.tier_basis === 'goal_attainment' && tier.max_percent !== ''
        ? Number(tier.max_percent)
        : null,
    rate_percent: Number(tier.rate_percent || 0),
  })),
  bonuses: form.bonuses.map(bonus => ({
    attainment_percent: Number(bonus.attainment_percent || 0),
    percent: Number(bonus.percent || 0),
    amount_cents: parseMoneyToCents(bonus.amount_value),
  })),
});

const planErrors = computed(() => {
  const errors = [];
  if (!form.name.trim()) errors.push('Informe o nome do plano.');
  if (form.starts_on && form.ends_on && form.starts_on > form.ends_on) {
    errors.push('A data final deve ser posterior à data inicial.');
  }
  if (Number(form.rate_percent || 0) < 0) {
    errors.push('A taxa padrão não pode ser negativa.');
  }
  if (Number(form.share_percent || 0) <= 0 || Number(form.share_percent) > 100) {
    errors.push('O rateio deve ficar entre 0,001% e 100%.');
  }
  if (form.tier_basis === 'goal_attainment' && !form.goal_ids.length) {
    errors.push('Vincule ao menos uma meta para faixas por atingimento.');
  }
  form.tiers.forEach((tier, index) => {
    const min =
      form.tier_basis === 'goal_attainment'
        ? Number(tier.min_percent || 0)
        : parseMoneyToCents(tier.min_value);
    const max =
      form.tier_basis === 'goal_attainment'
        ? tier.max_percent === ''
          ? null
          : Number(tier.max_percent)
        : tier.max_value === ''
          ? null
          : parseMoneyToCents(tier.max_value);
    if (min < 0 || Number(tier.rate_percent || 0) < 0) {
      errors.push(`Faixa ${index + 1}: valores negativos não são permitidos.`);
    }
    if (max !== null && max < min) {
      errors.push(`Faixa ${index + 1}: limite máximo menor que o mínimo.`);
    }
  });
  return errors;
});

const stepIsValid = computed(() => {
  if (planStep.value === 1) {
    return Boolean(form.name.trim()) && (!form.starts_on || !form.ends_on || form.starts_on <= form.ends_on);
  }
  if (planStep.value === 2) {
    return Number(form.rate_percent || 0) >= 0;
  }
  if (planStep.value === 3) {
    return (
      form.tiers.length > 0 &&
      (form.tier_basis !== 'goal_attainment' || form.goal_ids.length > 0) &&
      !planErrors.value.some(message => message.startsWith('Faixa'))
    );
  }
  if (planStep.value === 4) {
    return Number(form.share_percent || 0) > 0 && Number(form.share_percent || 0) <= 100;
  }
  return planErrors.value.length === 0;
});

const nextPlanStep = () => {
  if (!stepIsValid.value) {
    useAlert(planErrors.value[0] || 'Revise os campos obrigatórios desta etapa.');
    return;
  }
  planStep.value = Math.min(5, planStep.value + 1);
};

const previousPlanStep = () => {
  planStep.value = Math.max(1, planStep.value - 1);
};

const simulatePlan = async () => {
  try {
    const { data } = await commissionProgramsAPI.simulate({
      rules: buildRules(),
      sale: {
        total_cents: parseMoneyToCents(sim.total),
        monthly_cents: parseMoneyToCents(sim.monthly),
        received_cents: parseMoneyToCents(sim.received),
        margin_cents: parseMoneyToCents(sim.margin),
      },
      attainment_percent: Number(sim.attainment || 0),
      share_percent: Number(form.share_percent || 100),
    });
    simulationResult.value = data;
  } catch (error) {
    useAlert(
      error.response?.data?.message || 'Não foi possível simular o plano.'
    );
  }
};

const savePlan = async publish => {
  if (planErrors.value.length) {
    useAlert(planErrors.value[0]);
    return;
  }
  saving.value = true;
  const rules = buildRules();
  const payload = {
    commission_program: {
      name: form.name,
      release_condition: form.release_condition,
      starts_on: form.starts_on || null,
      ends_on: form.ends_on || null,
      active: Boolean(publish),
      rules,
    },
  };
  try {
    if (editingPlanId.value) {
      await commissionProgramsAPI.update(editingPlanId.value, payload);
    } else {
      await commissionProgramsAPI.create(payload);
    }
    useAlert(publish ? 'Plano publicado e salvo.' : 'Plano salvo como rascunho.');
    resetPlan();
    await load();
    goTab('plans');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        error.response?.data?.message ||
        'Não foi possível salvar o plano.'
    );
  } finally {
    saving.value = false;
  }
};

watch(() => selected.value?.id, () => { reversalReason.value = ''; });
const updateCommission = async (row, status) => {
  if (status === 'reversed' && !reversalReason.value.trim()) { useAlert(t('CRM.WORKFLOW_UI.REVERSAL_REQUIRED')); return; }
  saving.value = true;
  try {
    const { data } = await commissionsAPI.update(row.id, {
      commission: { status, ...(status === 'reversed' ? { reversal_reason:reversalReason.value.trim() } : {}) },
    });
    selected.value = data;
    await load();
    useAlert('Comissão atualizada.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        'Não foi possível atualizar a comissão.'
    );
  } finally {
    saving.value = false;
  }
};

watch(
  () => route.params.section,
  value => {
    tab.value = validSections.includes(value) ? value : 'current';
  }
);
onMounted(load);
</script>

<template>
  <div class="h-full overflow-auto bg-slate-50 p-4 sm:p-6">
    <header class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <p class="text-xs font-semibold text-blue-700">CRM / Comercial</p>
        <h2 class="text-2xl font-bold">Comissões</h2>
        <p class="text-sm text-slate-500">
          Planos, apuração, aprovação e pagamento sobre pedidos reais.
        </p>
      </div>
      <button
        class="rounded-lg border bg-white px-4 py-2 font-semibold"
        :disabled="loading"
        @click="load"
      >
        Atualizar
      </button>
    </header>

    <nav class="my-4 flex gap-2 overflow-x-auto border-b bg-white p-2">
      <button
        v-for="item in tabs"
        :key="item[0]"
        class="shrink-0 rounded-lg px-3 py-2 text-sm font-semibold"
        :class="tab === item[0] ? 'bg-blue-600 text-white' : 'text-slate-600'"
        @click="goTab(item[0])"
      >
        {{ item[1] }}
      </button>
    </nav>


      <div v-if="loadErrors.length" role="alert" class="mb-4 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900"><p v-for="message in loadErrors" :key="message">{{ message }}</p><button class="mt-2 rounded border border-amber-600 px-3 py-1 font-semibold" @click="load">{{ t('CRM.WORKFLOW_UI.RETRY') }}</button></div>
    <section class="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
        <article
          v-for="item in metrics"
          :key="item[0]"
          class="rounded-lg border bg-white p-4"
        >
          <p class="text-xs text-slate-500">{{ item[0] }}</p>
          <strong class="text-xl text-blue-700">{{ money(item[1]) }}</strong>
        </article>
      </section>

      <section v-if="tab === 'current'" class="mt-4 grid gap-4 xl:grid-cols-[1.2fr_.8fr]">
        <article class="rounded-2xl border bg-white p-5 shadow-sm">
          <div class="flex items-center justify-between"><div><h3 class="font-bold">Evolução mensal</h3><p class="text-xs text-slate-500">Prevista, liberada e paga nos últimos meses.</p></div><i class="i-lucide-chart-column-big size-5 text-blue-600"/></div>
          <div class="mt-5 grid min-h-56 grid-cols-8 items-end gap-3">
            <div v-for="item in monthlyEvolution" :key="item.key" class="flex h-52 flex-col justify-end gap-1">
              <div class="rounded-t bg-blue-200" :style="{height:`${Math.max(3,item.forecast/chartMax*100)}%`}"/>
              <div class="rounded-t bg-amber-400" :style="{height:`${Math.max(3,item.released/chartMax*100)}%`}"/>
              <div class="rounded-t bg-emerald-500" :style="{height:`${Math.max(3,item.paid/chartMax*100)}%`}"/>
              <span class="pt-1 text-center text-[10px] text-slate-500">{{item.label}}</span>
            </div>
          </div>
        </article>
        <article class="rounded-2xl border bg-white p-5 shadow-sm">
          <h3 class="font-bold">Comissão por vendedor</h3>
          <div class="mt-4 space-y-3">
            <div v-for="item in sellerChart" :key="item.id">
              <div class="flex justify-between text-xs"><span class="font-medium">{{item.name}}</span><b>{{money(item.value)}}</b></div>
              <div class="mt-1 h-2 rounded-full bg-slate-100"><div class="h-full rounded-full bg-violet-500" :style="{width:`${Math.max(2,item.value/chartMax*100)}%`}" /></div>
            </div>
            <p v-if="!sellerChart.length" class="py-8 text-center text-sm text-slate-500">Sem dados por vendedor.</p>
          </div>
        </article>
      </section>

      <section v-if="tab === 'current'" class="mt-4 rounded-2xl border bg-white p-5 shadow-sm">
        <h3 class="font-bold">Comissão por produto</h3>
        <p role="status" class="mt-3 rounded-xl border border-amber-300 bg-amber-50 p-3 text-sm text-amber-900">{{ t('CRM.HOMOLOGATION.PRODUCT_COMMISSION_PENDING') }}</p>
      </section>

      <section
        v-if="tab === 'plans'"
        class="mt-4 rounded-lg border bg-white p-4"
      >
        <div class="flex items-center justify-between">
          <div>
            <h3 class="font-bold">Planos persistidos</h3>
            <p class="text-sm text-slate-500">
              Regras usadas pela apuração automática de pedidos.
            </p>
          </div>
          <button
            class="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white"
            @click="
              resetPlan();
              goTab('new');
            "
          >
            Novo plano
          </button>
        </div>
        <p v-if="!plans.length" class="py-10 text-center text-slate-500">
          Nenhum plano cadastrado.
        </p>
        <div v-else class="mt-4 overflow-x-auto">
          <table class="w-full min-w-[760px] text-sm">
            <thead>
              <tr class="border-b text-left text-xs uppercase text-slate-500">
                <th class="p-2">Plano</th>
                <th>Vigência</th>
                <th>Evento</th>
                <th>Taxa base</th>
                <th>Comissões</th>
                <th>Status</th>
                <th />
              </tr>
            </thead>
            <tbody>
              <tr v-for="plan in plans" :key="plan.id" class="border-b">
                <td class="p-3 font-semibold">{{ plan.name }}</td>
                <td>
                  {{ plan.starts_on || 'Sem início' }} a
                  {{ plan.ends_on || 'sem fim' }}
                </td>
                <td>{{ plan.release_condition }}</td>
                <td>{{ plan.rules?.rate_percent || 0 }}%</td>
                <td>{{ plan.commissions_count }}</td>
                <td>{{ plan.active ? 'Publicado' : 'Inativo' }}</td>
                <td>
                  <button
                    class="rounded-lg border px-3 py-1.5"
                    @click="editPlan(plan)"
                  >
                    Editar
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <form
        v-else-if="tab === 'new'"
        class="mt-4 space-y-4"
        @submit.prevent
      >
        <section class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <div class="border-b border-slate-200 px-5 py-4">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <p class="text-xs font-semibold uppercase tracking-wide text-blue-600">
                  Planos de comissão
                </p>
                <h3 class="text-xl font-bold text-slate-900">
                  {{ editingPlanId ? 'Editar plano de comissão' : 'Novo plano de comissão' }}
                </h3>
                <p class="text-sm text-slate-500">
                  Configure regras reais de cálculo e revise antes de publicar.
                </p>
              </div>
              <button type="button" class="rounded-xl border px-4 py-2 text-sm font-semibold" @click="resetPlan(); goTab('plans')">
                Voltar aos planos
              </button>
            </div>
          </div>
          <div class="grid grid-cols-5 border-b border-slate-200 bg-slate-50/70">
            <button
              v-for="(item, index) in planSteps"
              :key="item[0]"
              type="button"
              class="relative flex min-w-0 items-center justify-center gap-2 px-2 py-4 text-xs font-semibold sm:text-sm"
              :class="planStep === index + 1 ? 'text-blue-700' : planStep > index + 1 ? 'text-emerald-700' : 'text-slate-500'"
              @click="planStep = index + 1"
            >
              <span
                class="grid size-8 shrink-0 place-content-center rounded-full font-bold"
                :class="planStep === index + 1 ? 'bg-blue-600 text-white' : planStep > index + 1 ? 'bg-emerald-600 text-white' : 'bg-slate-200 text-slate-600'"
              >
                <i v-if="planStep > index + 1" class="i-lucide-check size-4" />
                <span v-else>{{ index + 1 }}</span>
              </span>
              <span class="hidden xl:block">{{ item[0] }}</span>
              <span v-if="planStep === index + 1" class="absolute inset-x-0 bottom-0 h-0.5 bg-blue-600" />
            </button>
          </div>
        </section>

        <div class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_330px]">
          <div class="min-w-0 space-y-4">
            <section v-if="planStep === 1" class="rounded-2xl border bg-white p-5 shadow-sm">
              <div class="mb-5 flex items-center gap-3">
                <span class="grid size-10 place-content-center rounded-xl bg-blue-50 text-blue-600"><i class="i-lucide-badge-percent size-5" /></span>
                <div><h4 class="font-bold">Dados gerais</h4><p class="text-xs text-slate-500">Vigência, participantes, tipo e evento gerador.</p></div>
              </div>
              <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
                <label class="md:col-span-2">Nome do plano *
                  <input v-model="form.name" required class="mt-1 w-full rounded-xl border border-slate-200 p-2.5" placeholder="Ex.: Plano Comercial 2026" />
                </label>
                <label>Início
                  <input v-model="form.starts_on" type="date" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5" />
                </label>
                <label>Término
                  <input v-model="form.ends_on" type="date" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5" />
                </label>
                <label class="md:col-span-2">Descrição
                  <textarea v-model="form.description" rows="3" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5" placeholder="Objetivo e regras gerais deste plano." />
                </label>
                <label>Tipo do plano
                  <select v-model="form.plan_type" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5">
                    <option value="individual">Individual</option>
                    <option value="team">Equipe</option>
                    <option value="shared">Compartilhado</option>
                  </select>
                </label>
                <label>Evento gerador
                  <select v-model="form.release_condition" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5">
                    <option value="order_approved">Pedido aprovado</option>
                    <option value="contract_signed">Contrato assinado</option>
                    <option value="payment_received">Pagamento recebido</option>
                    <option value="implementation_completed">Implantação concluída</option>
                  </select>
                </label>
              </div>
              <div class="mt-5 grid gap-4 lg:grid-cols-2">
                <label class="rounded-xl border border-slate-200 p-4">
                  <span class="font-semibold">Vendedores participantes</span>
                  <select v-model="form.user_ids" multiple class="mt-2 h-32 w-full rounded-lg border p-2">
                    <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
                  </select>
                  <span class="mt-1 block text-xs text-slate-500">Sem seleção, a regra não restringe vendedores.</span>
                </label>
                <label class="rounded-xl border border-slate-200 p-4">
                  <span class="font-semibold">Equipes participantes</span>
                  <select v-model="form.team_ids" multiple class="mt-2 h-32 w-full rounded-lg border p-2">
                    <option v-for="team in teams" :key="team.id" :value="team.id">{{ team.name }}</option>
                  </select>
                  <span class="mt-1 block text-xs text-slate-500">A equipe é validada contra os vínculos reais da conta.</span>
                </label>
              </div>
            </section>

            <section v-else-if="planStep === 2" class="rounded-2xl border bg-white p-5 shadow-sm">
              <div class="mb-5 flex items-center gap-3">
                <span class="grid size-10 place-content-center rounded-xl bg-indigo-50 text-indigo-600"><i class="i-lucide-calculator size-5" /></span>
                <div><h4 class="font-bold">Base comissionável e regras de cálculo</h4><p class="text-xs text-slate-500">A mesma regra é usada na simulação e na apuração automática.</p></div>
              </div>
              <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
                <label>Base comissionável
                  <select v-model="form.base" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5">
                    <option value="total_cents">Valor do pedido</option>
                    <option value="monthly_cents">MRR / recorrência</option>
                    <option value="received_cents">Valor recebido</option>
                    <option value="margin_cents">Margem informada no pedido</option>
                  </select>
                </label>
                <label>Taxa padrão (%)
                  <input v-model.number="form.rate_percent" type="number" min="0" step="0.001" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5" />
                </label>
                <label>Rateio padrão (%)
                  <input v-model.number="form.share_percent" type="number" min="0.001" max="100" step="0.001" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5" />
                </label>
                <label>Critério das faixas
                  <select v-model="form.tier_basis" class="mt-1 w-full rounded-xl border border-slate-200 p-2.5">
                    <option value="sales_value">Valor vendido</option>
                    <option value="goal_attainment">Atingimento de meta</option>
                  </select>
                </label>
              </div>
              <div class="mt-5 grid gap-3 md:grid-cols-2">
                <label class="flex items-start gap-3 rounded-xl border p-4">
                  <input v-model="form.requires_approval" type="checkbox" class="mt-1" />
                  <span><strong class="block">Exigir aprovação antes de liberar</strong><small class="text-slate-500">A comissão nasce em aprovação e só pode ser paga depois da liberação.</small></span>
                </label>
                <div class="rounded-xl border border-blue-100 bg-blue-50 p-4 text-sm text-blue-800">
                  <strong class="block">Evento e base são independentes</strong>
                  O evento define quando apurar; a base define sobre qual valor o cálculo será feito.
                </div>
              </div>
            </section>

            <section v-else-if="planStep === 3" class="space-y-4">
              <article class="rounded-2xl border bg-white p-5 shadow-sm">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div><h4 class="font-bold">Faixas de comissão</h4><p class="text-xs text-slate-500">Faixas por valor vendido e por atingimento usam limites diferentes.</p></div>
                  <button type="button" class="rounded-xl border px-3 py-2 text-sm font-semibold" @click="addTier">Adicionar faixa</button>
                </div>
                <div v-for="(tier, index) in form.tiers" :key="index" class="mt-3 grid gap-3 rounded-xl border border-slate-200 bg-slate-50/60 p-3 md:grid-cols-[1fr_1fr_1fr_auto]">
                  <template v-if="form.tier_basis === 'sales_value'">
                    <label>Venda mínima (R$)<input v-model="tier.min_value" inputmode="decimal" class="mt-1 w-full rounded-lg border p-2" /></label>
                    <label>Venda máxima (R$)<input v-model="tier.max_value" inputmode="decimal" class="mt-1 w-full rounded-lg border p-2" placeholder="Sem limite" /></label>
                  </template>
                  <template v-else>
                    <label>Atingimento mínimo (%)<input v-model.number="tier.min_percent" type="number" min="0" step="0.01" class="mt-1 w-full rounded-lg border p-2" /></label>
                    <label>Atingimento máximo (%)<input v-model="tier.max_percent" type="number" min="0" step="0.01" class="mt-1 w-full rounded-lg border p-2" placeholder="Sem limite" /></label>
                  </template>
                  <label>Comissão (%)<input v-model.number="tier.rate_percent" type="number" min="0" step="0.001" class="mt-1 w-full rounded-lg border p-2" /></label>
                  <button type="button" title="Remover faixa" class="self-end rounded-lg border border-red-200 p-2 text-red-600" @click="removeTier(index)"><i class="i-lucide-trash-2 size-4" /></button>
                </div>
              </article>
              <article class="rounded-2xl border bg-white p-5 shadow-sm">
                <div class="grid gap-4 lg:grid-cols-[1fr_.8fr]">
                  <label>Metas vinculadas
                    <select v-model="form.goal_ids" multiple class="mt-2 h-36 w-full rounded-lg border p-2">
                      <option v-for="goal in goals" :key="goal.id" :value="goal.id">
                        {{ goal.name || `Meta #${goal.id}` }} · {{ goal.period_start }} a {{ goal.period_end }}
                      </option>
                    </select>
                    <span v-if="form.tier_basis === 'goal_attainment'" class="mt-1 block text-xs font-semibold text-amber-700">Obrigatório para faixas por atingimento.</span>
                  </label>
                  <div>
                    <div class="flex items-center justify-between"><div><h5 class="font-semibold">Bônus por atingimento</h5><p class="text-xs text-slate-500">Somados quando o percentual mínimo for alcançado.</p></div><button type="button" class="rounded-lg border px-2 py-1 text-xs" @click="addBonus">Adicionar</button></div>
                    <div v-for="(bonus,index) in form.bonuses" :key="index" class="mt-2 grid grid-cols-[1fr_1fr_1fr_auto] gap-2">
                      <input v-model.number="bonus.attainment_percent" type="number" min="0" class="rounded-lg border p-2" title="Atingimento mínimo %" placeholder="Meta %" />
                      <input v-model.number="bonus.percent" type="number" min="0" step="0.01" class="rounded-lg border p-2" title="Bônus percentual" placeholder="Bônus %" />
                      <input v-model="bonus.amount_value" inputmode="decimal" class="rounded-lg border p-2" title="Bônus fixo em reais" placeholder="Bônus R$" />
                      <button type="button" class="rounded-lg border p-2 text-red-600" @click="removeBonus(index)">×</button>
                    </div>
                    <p v-if="!form.bonuses.length" class="mt-4 rounded-lg bg-slate-50 p-3 text-xs text-slate-500">Nenhum bônus adicional configurado.</p>
                  </div>
                </div>
              </article>
            </section>

            <section v-else-if="planStep === 4" class="space-y-4">
              <article class="rounded-2xl border bg-white p-5 shadow-sm">
                <div class="mb-4"><h4 class="font-bold">Produtos e serviços</h4><p class="text-xs text-slate-500">O plano só considera os produtos selecionados. Sem seleção, considera todos.</p></div>
                <select v-model="form.product_ids" multiple class="h-56 w-full rounded-xl border border-slate-200 p-3">
                  <option v-for="product in products" :key="product.id" :value="product.id">{{ product.name }}</option>
                </select>
              </article>
              <article class="rounded-2xl border bg-white p-5 shadow-sm">
                <h4 class="font-bold">Equipes, participantes e rateio</h4>
                <div class="mt-4 grid gap-4 lg:grid-cols-3">
                  <label>Vendedores
                    <select v-model="form.user_ids" multiple class="mt-1 h-36 w-full rounded-lg border p-2">
                      <option v-for="agent in agents" :key="agent.id" :value="agent.id">{{ agent.name }}</option>
                    </select>
                  </label>
                  <label>Equipes
                    <select v-model="form.team_ids" multiple class="mt-1 h-36 w-full rounded-lg border p-2">
                      <option v-for="team in teams" :key="team.id" :value="team.id">{{ team.name }}</option>
                    </select>
                  </label>
                  <div class="rounded-xl border p-4">
                    <label>Participação aplicada ao cálculo (%)
                      <input v-model.number="form.share_percent" type="number" min="0.001" max="100" step="0.001" class="mt-1 w-full rounded-lg border p-2" />
                    </label>
                    <p class="mt-3 text-xs text-slate-500">O valor é gravado na memória da comissão e mantém simulação e apuração consistentes.</p>
                  </div>
                </div>
              </article>
            </section>

            <section v-else class="space-y-4">
              <div class="grid gap-4 lg:grid-cols-2">
                <article class="rounded-2xl border bg-white p-5 shadow-sm">
                  <div class="flex justify-between gap-3"><h4 class="font-bold">1. Dados gerais</h4><button type="button" class="text-sm font-semibold text-blue-600" @click="planStep=1">Editar</button></div>
                  <dl class="mt-3 grid grid-cols-2 gap-2 text-sm"><dt class="text-slate-500">Plano</dt><dd class="font-semibold">{{form.name}}</dd><dt class="text-slate-500">Período</dt><dd>{{form.starts_on||'Sem início'}} a {{form.ends_on||'sem fim'}}</dd><dt class="text-slate-500">Evento</dt><dd>{{form.release_condition}}</dd><dt class="text-slate-500">Tipo</dt><dd>{{form.plan_type}}</dd></dl>
                </article>
                <article class="rounded-2xl border bg-white p-5 shadow-sm">
                  <div class="flex justify-between gap-3"><h4 class="font-bold">2. Regras de cálculo</h4><button type="button" class="text-sm font-semibold text-blue-600" @click="planStep=2">Editar</button></div>
                  <dl class="mt-3 grid grid-cols-2 gap-2 text-sm"><dt class="text-slate-500">Base</dt><dd>{{form.base}}</dd><dt class="text-slate-500">Taxa padrão</dt><dd>{{form.rate_percent}}%</dd><dt class="text-slate-500">Critério das faixas</dt><dd>{{form.tier_basis==='goal_attainment'?'Atingimento de meta':'Valor vendido'}}</dd><dt class="text-slate-500">Aprovação</dt><dd>{{form.requires_approval?'Obrigatória':'Liberação automática'}}</dd></dl>
                </article>
                <article class="rounded-2xl border bg-white p-5 shadow-sm">
                  <div class="flex justify-between gap-3"><h4 class="font-bold">3. Faixas e metas</h4><button type="button" class="text-sm font-semibold text-blue-600" @click="planStep=3">Editar</button></div>
                  <p class="mt-3 text-sm">{{form.tiers.length}} faixa(s) · {{form.goal_ids.length}} meta(s) vinculada(s) · {{form.bonuses.length}} bônus.</p>
                </article>
                <article class="rounded-2xl border bg-white p-5 shadow-sm">
                  <div class="flex justify-between gap-3"><h4 class="font-bold">4. Produtos e equipes</h4><button type="button" class="text-sm font-semibold text-blue-600" @click="planStep=4">Editar</button></div>
                  <p class="mt-3 text-sm">{{form.product_ids.length || 'Todos os'}} produto(s) · {{form.team_ids.length || 'Todas as'}} equipe(s) · rateio {{form.share_percent}}%.</p>
                </article>
              </div>

              <article class="rounded-2xl border bg-white p-5 shadow-sm">
                <div class="flex flex-wrap items-center justify-between gap-3">
                  <div><h4 class="font-bold">Simulação final</h4><p class="text-xs text-slate-500">Executada no mesmo motor de regras usado pela apuração.</p></div>
                  <button type="button" class="rounded-xl bg-indigo-600 px-4 py-2 text-sm font-semibold text-white" @click="simulatePlan">Simular cálculo</button>
                </div>
                <div class="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
                  <label>Venda (R$)<input v-model="sim.total" class="mt-1 w-full rounded-lg border p-2" /></label>
                  <label>MRR (R$)<input v-model="sim.monthly" class="mt-1 w-full rounded-lg border p-2" /></label>
                  <label>Recebido (R$)<input v-model="sim.received" class="mt-1 w-full rounded-lg border p-2" /></label>
                  <label>Margem (R$)<input v-model="sim.margin" class="mt-1 w-full rounded-lg border p-2" /></label>
                  <label>Atingimento (%)<input v-model.number="sim.attainment" type="number" class="mt-1 w-full rounded-lg border p-2" /></label>
                </div>
                <div v-if="simulationResult" class="mt-4 grid gap-3 sm:grid-cols-4">
                  <div class="rounded-xl bg-slate-50 p-4"><p class="text-xs text-slate-500">Base</p><strong>{{money(simulationResult.base_cents)}}</strong></div>
                  <div class="rounded-xl bg-slate-50 p-4"><p class="text-xs text-slate-500">Taxa</p><strong>{{simulationResult.rate_percent}}%</strong></div>
                  <div class="rounded-xl bg-slate-50 p-4"><p class="text-xs text-slate-500">Bônus</p><strong>{{money(simulationResult.bonus_cents)}}</strong></div>
                  <div class="rounded-xl bg-emerald-50 p-4"><p class="text-xs text-emerald-700">Comissão estimada</p><strong class="text-emerald-700">{{money(simulationResult.commission_cents)}}</strong></div>
                </div>
              </article>

              <article class="rounded-2xl border p-5" :class="planErrors.length ? 'border-amber-200 bg-amber-50' : 'border-emerald-200 bg-emerald-50'">
                <h4 class="font-bold" :class="planErrors.length ? 'text-amber-900' : 'text-emerald-900'">Validação do plano</h4>
                <p v-if="!planErrors.length" class="mt-2 text-sm text-emerald-800">Informações mínimas consistentes para salvar/publicar.</p>
                <ul v-else class="mt-2 list-disc space-y-1 pl-5 text-sm text-amber-800"><li v-for="error in planErrors" :key="error">{{error}}</li></ul>
              </article>
            </section>
          </div>

          <aside class="h-fit rounded-2xl border bg-white p-5 shadow-sm xl:sticky xl:top-3">
            <p class="text-xs font-semibold uppercase tracking-wide text-blue-600">Resumo do plano</p>
            <h4 class="mt-1 truncate text-lg font-bold">{{ form.name || 'Plano sem nome' }}</h4>
            <dl class="mt-4 grid grid-cols-[1fr_auto] gap-x-3 gap-y-3 text-sm">
              <dt class="text-slate-500">Etapa</dt><dd class="font-semibold">{{planStep}}/5</dd>
              <dt class="text-slate-500">Evento</dt><dd class="font-semibold">{{form.release_condition}}</dd>
              <dt class="text-slate-500">Base</dt><dd class="font-semibold">{{form.base}}</dd>
              <dt class="text-slate-500">Taxa</dt><dd class="font-semibold">{{form.rate_percent}}%</dd>
              <dt class="text-slate-500">Faixas</dt><dd class="font-semibold">{{form.tiers.length}}</dd>
              <dt class="text-slate-500">Metas</dt><dd class="font-semibold">{{form.goal_ids.length}}</dd>
              <dt class="text-slate-500">Produtos</dt><dd class="font-semibold">{{form.product_ids.length || 'Todos'}}</dd>
              <dt class="text-slate-500">Rateio</dt><dd class="font-semibold">{{form.share_percent}}%</dd>
            </dl>
            <div class="mt-5 rounded-xl bg-blue-50 p-4 text-xs text-blue-800">
              <strong class="block">Regra operacional</strong>
              O plano só gera comissão quando o evento configurado realmente ocorrer no CRM.
            </div>
          </aside>
        </div>

        <div class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border bg-white p-4 shadow-sm">
          <button type="button" class="rounded-xl border px-4 py-2 font-semibold" @click="planStep === 1 ? (resetPlan(), goTab('plans')) : previousPlanStep()">
            {{ planStep === 1 ? 'Cancelar' : 'Voltar' }}
          </button>
          <div class="text-xs text-slate-500">Etapa {{planStep}} de 5 · {{planSteps[planStep-1][1]}}</div>
          <div class="flex gap-2">
            <template v-if="planStep < 5">
              <button type="button" class="rounded-xl bg-blue-600 px-5 py-2 font-semibold text-white disabled:opacity-50" :disabled="!stepIsValid" @click="nextPlanStep">Avançar</button>
            </template>
            <template v-else>
              <button type="button" class="rounded-xl border border-slate-300 px-4 py-2 font-semibold" :disabled="saving || planErrors.length" @click="savePlan(false)">{{saving?'Salvando...':'Salvar rascunho'}}</button>
              <button type="button" class="rounded-xl bg-blue-600 px-5 py-2 font-semibold text-white disabled:opacity-50" :disabled="saving || planErrors.length" @click="savePlan(true)">{{saving?'Publicando...':'Publicar plano'}}</button>
            </template>
          </div>
        </div>
      </form>

      <section v-else-if="tab === 'history'" class="mt-4 rounded-2xl border bg-white p-5 shadow-sm">
        <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div><h3 class="font-bold">Histórico de eventos</h3><p class="text-sm text-slate-500">Alterações persistidas de criação, atualização, liberação, pagamento e estorno.</p></div>
          <select v-model="sellerFilter" class="rounded-lg border px-3 py-2 text-sm"><option value="all">Todos os vendedores</option><option v-for="seller in uniqueSellers" :key="seller.id" :value="String(seller.id)">{{seller.name}}</option></select>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full min-w-[760px] text-sm">
            <thead><tr class="border-b text-left text-xs uppercase text-slate-500"><th class="p-2">Data</th><th>Pedido</th><th>Vendedor</th><th>Evento</th><th>Antes</th><th>Depois</th></tr></thead>
            <tbody><tr v-for="event in filteredHistory" :key="event.id" class="border-b"><td class="p-3">{{new Date(event.created_at).toLocaleString('pt-BR')}}</td><td>{{rows.find(r=>Number(r.id)===Number(event.commission_id))?.order?.order_number||`#${event.commission_id}`}}</td><td>{{rows.find(r=>Number(r.id)===Number(event.commission_id))?.user?.name||'—'}}</td><td class="font-semibold">{{event.event_type}}</td><td>{{event.from_value?.status||'—'}}</td><td>{{event.to_value?.status||'—'}}</td></tr></tbody>
          </table>
        </div>
        <p v-if="!filteredHistory.length" class="py-10 text-center text-sm text-slate-500">Ainda não existem eventos de comissão registrados neste ambiente.</p>
      </section>

      <div v-else class="mt-4 grid gap-4 xl:grid-cols-[minmax(0,1fr)_340px]">
        <section class="rounded-lg border bg-white p-4">
          <div class="mb-3 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h3 class="font-bold">
                {{ tabs.find(item => item[0] === tab)?.[1] }}
              </h3>
              <p class="text-sm text-slate-500">
                {{ rowsForTab.length }} registro(s) persistido(s)
              </p>
            </div>
            <div class="flex flex-wrap gap-2">
              <input v-model="search" class="rounded-lg border px-3 py-2 text-sm" placeholder="Buscar pedido ou vendedor" />
              <select v-model="statusFilter" class="rounded-lg border px-3 py-2 text-sm"><option value="all">Todos os status</option><option v-for="statusName in ['forecast','pending_approval','released','paid','reversed']" :key="statusName" :value="statusName">{{statusName}}</option></select>
              <select v-if="tab!=='mine'" v-model="sellerFilter" class="rounded-lg border px-3 py-2 text-sm"><option value="all">Todos os vendedores</option><option v-for="seller in uniqueSellers" :key="seller.id" :value="String(seller.id)">{{seller.name}}</option></select>
              <select v-model="programFilter" class="rounded-lg border px-3 py-2 text-sm"><option value="all">Todos os planos</option><option v-for="program in uniquePrograms" :key="program.id" :value="String(program.id)">{{program.name}}</option></select>
            </div>
          </div>
          <p v-if="loading" class="py-10 text-center text-slate-500">
            Carregando dados...
          </p>
          <p
            v-else-if="!rowsForTab.length"
            class="py-10 text-center text-slate-500"
          >
            Nenhuma comissão encontrada nesta visão.
          </p>
          <div v-else class="overflow-x-auto">
            <table class="w-full min-w-[820px] text-sm">
              <thead>
                <tr class="border-b text-left text-xs uppercase text-slate-500">
                  <th class="p-2">Pedido</th>
                  <th>Vendedor</th>
                  <th>Plano</th>
                  <th>Base</th>
                  <th>Taxa</th>
                  <th>Comissão</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in pagedRows"
                  :key="row.id"
                  class="cursor-pointer border-b hover:bg-slate-50"
                  @click="selected = row"
                >
                  <td class="p-3 font-semibold text-blue-700">
                    {{ row.order.order_number }}
                  </td>
                  <td>{{ row.user.name }}</td>
                  <td>{{ row.program?.name || 'Manual' }}</td>
                  <td>{{ money(row.base_cents) }}</td>
                  <td>{{ row.rate_percent }}%</td>
                  <td>{{ money(row.commission_cents) }}</td>
                  <td>{{ row.status }}</td>
                </tr>
              </tbody>
            </table>
          </div>
          <div v-if="rowsForTab.length" class="mt-4 flex flex-wrap items-center justify-between gap-3 border-t pt-3">
            <span class="text-xs text-slate-500">Página {{page}} de {{pageCount}} · {{rowsForTab.length}} registro(s)</span>
            <div class="flex gap-2"><select v-model.number="perPage" class="rounded-lg border px-2 py-1 text-xs" @change="page=1"><option :value="10">10</option><option :value="20">20</option><option :value="50">50</option></select><button class="rounded-lg border px-3 py-1 text-xs disabled:opacity-40" :disabled="page<=1" @click="page--">Anterior</button><button class="rounded-lg border px-3 py-1 text-xs disabled:opacity-40" :disabled="page>=pageCount" @click="page++">Próxima</button></div>
          </div>
        </section>

        <aside class="rounded-lg border bg-white p-4">
          <template v-if="selected">
            <div class="flex justify-between">
              <h3 class="font-bold">{{ selected.order.order_number }}</h3>
              <button title="Fechar detalhe" @click="selected = null">×</button>
            </div>
            <dl class="mt-4 space-y-3 text-sm">
              <div>
                <dt class="text-slate-500">Vendedor</dt>
                <dd>{{ selected.user.name }}</dd>
              </div>
              <div>
                <dt class="text-slate-500">Plano aplicado</dt>
                <dd>{{ selected.program?.name || 'Lançamento manual' }}</dd>
              </div>
              <div>
                <dt class="text-slate-500">Memória de cálculo</dt>
                <dd>
                  {{ money(selected.base_cents) }} ×
                  {{ selected.rate_percent }}% =
                  {{ money(selected.commission_cents) }}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Status</dt>
                <dd>{{ selected.status }}</dd>
              </div>
            </dl>
            <div class="mt-5 grid gap-2">
              <button
                v-if="selected.status === 'pending_approval'"
                class="rounded-lg bg-emerald-600 p-2 font-semibold text-white"
                :disabled="saving"
                @click="updateCommission(selected, 'released')"
              >
                Aprovar e liberar
              </button>
              <button
                v-if="selected.status === 'released'"
                class="rounded-lg bg-blue-600 p-2 font-semibold text-white"
                :disabled="saving"
                @click="updateCommission(selected, 'paid')"
              >
                Registrar pagamento
              </button>
              <label v-if="selected.status !== 'reversed'" class="block w-full text-sm">{{ t('CRM.WORKFLOW_UI.REVERSAL_LABEL') }}<textarea v-model="reversalReason" rows="2" class="mt-1 w-full rounded-lg border p-2" :placeholder="t('CRM.WORKFLOW_UI.REVERSAL_PLACEHOLDER')" /></label>
              <button
                v-if="
                  selected.status !== 'reversed'
                "
                class="rounded-lg border border-red-300 p-2 text-red-700"
                :disabled="saving"
                @click="updateCommission(selected, 'reversed')"
              >
                Estornar
              </button>
            </div>
          </template>
          <template v-else>
            <h3 class="font-bold">Memória de cálculo</h3>
            <p class="mt-2 text-sm text-slate-500">
              Selecione uma comissão para consultar sua origem e executar as
              ações permitidas.
            </p>
          </template>
        </aside>
      </div>
  </div>
</template>
