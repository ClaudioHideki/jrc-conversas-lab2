<script setup>
/* eslint-disable vue/no-bare-strings-in-template */
import { computed, onMounted, reactive, ref } from 'vue';
import TeamsAPI from 'dashboard/api/teams';
import AgentsAPI from 'dashboard/api/agents';
import ProductsAPI from 'dashboard/api/crm/products';
import OrganizationStructureAPI from 'dashboard/api/crm/organizationStructure';
import {
  operationsQueuesAPI,
  operationsSlaPoliciesAPI,
} from 'dashboard/api/crm/commercialCycle';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  summary: { type: Object, default: () => ({}) },
  requests: { type: Array, default: () => [] },
});

const queues = ref([]);
const policies = ref([]);
const teams = ref([]);
const agents = ref([]);
const units = ref([]);
const companies = ref([]);
const products = ref([]);
const loading = ref(false);
const saving = ref(false);

const queueForm = reactive({
  name: '',
  code: '',
  operating_company_id: '',
  business_unit_id: '',
  team_id: '',
  user_id: '',
  request_kind: '',
  priority: '',
  product_id: '',
  assignment_strategy: 'manual',
  specialty: '',
  active: true,
});
const policyForm = reactive({
  name: '',
  operations_queue_id: '',
  request_kind: '',
  priority: '',
  product_id: '',
  first_action_minutes: '',
  stage_minutes: '',
  total_minutes: '',
  active: true,
  pause_statuses: 'waiting_customer',
  thresholds: '50,75,90,100',
  business_enabled: false,
  business_start: '08:00',
  business_end: '18:00',
  weekdays: '1,2,3,4,5',
  holidays: '',
  escalation_user_id: '',
});

const configuredQueues = computed(
  () => queues.value.filter(item => item.active).length
);
const configuredPolicies = computed(
  () => policies.value.filter(item => item.active && item.total_minutes).length
);

const queueStats = computed(() => {
  const map = new Map();
  props.requests
    .filter(
      item => !['completed', 'canceled', 'rejected'].includes(item.status)
    )
    .forEach(item => {
      const key = item.queue?.id || 'unrouted';
      if (!map.has(key))
        map.set(key, {
          id: key,
          name: item.queue?.name || 'Sem fila',
          total: 0,
          within: 0,
          watch: 0,
          attention: 0,
          critical: 0,
          overdue: 0,
        });
      const row = map.get(key);
      row.total += 1;
      const state = item.sla?.state || 'within';
      if (Object.prototype.hasOwnProperty.call(row, state)) row[state] += 1;
    });
  return [...map.values()].sort(
    (a, b) =>
      b.overdue - a.overdue || b.critical - a.critical || b.total - a.total
  );
});

const load = async () => {
  loading.value = true;
  try {
    const [
      queueResponse,
      policyResponse,
      teamResponse,
      agentResponse,
      orgResponse,
      productResponse,
    ] = await Promise.all([
      operationsQueuesAPI.list(),
      operationsSlaPoliciesAPI.list(),
      TeamsAPI.get(),
      AgentsAPI.get(),
      OrganizationStructureAPI.load(),
      ProductsAPI.list({ active: true }),
    ]);
    queues.value = queueResponse.data || [];
    policies.value = policyResponse.data || [];
    teams.value = teamResponse.data?.payload || teamResponse.data || [];
    agents.value = agentResponse.data || [];
    units.value = orgResponse.data?.business_units || [];
    companies.value = orgResponse.data?.operating_companies || [];
    products.value =
      productResponse.data?.payload || productResponse.data || [];
  } catch (error) {
    useAlert(
      error.response?.data?.message || 'Não foi possível carregar filas e SLAs.'
    );
  } finally {
    loading.value = false;
  }
};

const saveQueue = async () => {
  if (!queueForm.name.trim() || !queueForm.code.trim()) {
    useAlert('Informe nome e código da fila.');
    return;
  }
  saving.value = true;
  try {
    await operationsQueuesAPI.create({
      operations_queue: {
        ...queueForm,
        operating_company_id: queueForm.operating_company_id || null,
        business_unit_id: queueForm.business_unit_id || null,
        team_id: queueForm.team_id || null,
        settings: {
          ...(queueForm.user_id
            ? { user_ids: [Number(queueForm.user_id)] }
            : {}),
          ...(queueForm.request_kind
            ? { request_kinds: [queueForm.request_kind] }
            : {}),
          ...(queueForm.priority ? { priorities: [queueForm.priority] } : {}),
          ...(queueForm.product_id
            ? { product_ids: [Number(queueForm.product_id)] }
            : {}),
        },
        code: queueForm.code.trim().toUpperCase().replace(/\s+/g, '-'),
      },
    });
    Object.assign(queueForm, {
      name: '',
      code: '',
      operating_company_id: '',
      business_unit_id: '',
      team_id: '',
      user_id: '',
      request_kind: '',
      priority: '',
      product_id: '',
      assignment_strategy: 'manual',
      specialty: '',
      active: true,
    });
    await load();
    useAlert('Fila operacional criada.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        error.response?.data?.message ||
        'Não foi possível criar a fila.'
    );
  } finally {
    saving.value = false;
  }
};

const savePolicy = async () => {
  if (!policyForm.name.trim()) {
    useAlert('Informe o nome da política de SLA.');
    return;
  }
  saving.value = true;
  try {
    const toInteger = value => (value === '' ? null : Number(value));
    await operationsSlaPoliciesAPI.create({
      operations_sla_policy: {
        name: policyForm.name.trim(),
        scope_kind: 'backoffice',
        operations_queue_id: policyForm.operations_queue_id || null,
        request_kind: policyForm.request_kind || null,
        priority: policyForm.priority || null,
        conditions: policyForm.product_id
          ? { product_ids: [Number(policyForm.product_id)] }
          : {},
        first_action_minutes: toInteger(policyForm.first_action_minutes),
        stage_minutes: toInteger(policyForm.stage_minutes),
        total_minutes: toInteger(policyForm.total_minutes),
        active: policyForm.active,
        pause_statuses: policyForm.pause_statuses
          .split(',')
          .map(v => v.trim())
          .filter(Boolean),
        alert_thresholds: policyForm.thresholds
          .split(',')
          .map(Number)
          .filter(v => Number.isFinite(v) && v > 0),
        escalation: policyForm.escalation_user_id
          ? { user_id: Number(policyForm.escalation_user_id) }
          : {},
        business_hours: {
          enabled: policyForm.business_enabled,
          start: policyForm.business_start,
          end: policyForm.business_end,
          weekdays: policyForm.weekdays
            .split(',')
            .map(Number)
            .filter(Number.isFinite),
          holidays: policyForm.holidays
            .split(',')
            .map(v => v.trim())
            .filter(Boolean),
        },
      },
    });
    Object.assign(policyForm, {
      name: '',
      operations_queue_id: '',
      request_kind: '',
      priority: '',
      product_id: '',
      first_action_minutes: '',
      stage_minutes: '',
      total_minutes: '',
      active: true,
      pause_statuses: 'waiting_customer',
      thresholds: '50,75,90,100',
      business_enabled: false,
      business_start: '08:00',
      business_end: '18:00',
      weekdays: '1,2,3,4,5',
      holidays: '',
      escalation_user_id: '',
    });
    await load();
    useAlert('Política de SLA criada.');
  } catch (error) {
    useAlert(
      error.response?.data?.errors?.join(', ') ||
        error.response?.data?.message ||
        'Não foi possível criar a política.'
    );
  } finally {
    saving.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="space-y-4">
    <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">Dentro do prazo</p>
        <strong class="text-2xl text-emerald-600">{{
          summary.within_sla || 0
        }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">50% consumido</p>
        <strong class="text-2xl text-yellow-600">{{
          summary.watch || 0
        }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">Atenção</p>
        <strong class="text-2xl text-amber-500">{{
          summary.attention || 0
        }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">Crítico</p>
        <strong class="text-2xl text-orange-600">{{
          summary.critical || 0
        }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">Vencido</p>
        <strong class="text-2xl text-red-600">{{
          summary.overdue || 0
        }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">Filas ativas</p>
        <strong class="text-2xl">{{ configuredQueues }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">SLAs configurados</p>
        <strong class="text-2xl">{{ configuredPolicies }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">Cumprimento SLA</p>
        <strong class="text-2xl">{{
          summary.sla_compliance_percent == null
            ? '—'
            : `${summary.sla_compliance_percent}%`
        }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">Tempo médio</p>
        <strong class="text-2xl">{{
          summary.average_resolution_minutes
            ? `${summary.average_resolution_minutes} min`
            : '—'
        }}</strong>
      </article>
      <article class="rounded-xl border bg-n-solid-2 p-4">
        <p class="text-xs text-n-slate-11">1ª ação vencida</p>
        <strong class="text-2xl text-red-600">{{
          summary.first_action_overdue || 0
        }}</strong>
      </article>
    </div>

    <div class="grid gap-4 xl:grid-cols-2">
      <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
        <h3 class="font-bold">Filas operacionais</h3>
        <p class="mt-1 text-sm text-n-slate-11">
          Roteamento por unidade, equipe e estratégia. O motor é central e pode
          ser reutilizado por outros módulos.
        </p>
        <form
          class="mt-4 grid gap-3 sm:grid-cols-2"
          @submit.prevent="saveQueue"
        >
          <label class="text-sm"
            >Nome<input
              v-model="queueForm.name"
              required
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="text-sm"
            >Código<input
              v-model="queueForm.code"
              required
              class="mt-1 w-full rounded-lg border p-2"
              placeholder="BACKOFFICE-SP"
          /></label>
          <label class="text-sm"
            >Empresa operacional<select
              v-model="queueForm.operating_company_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todas</option>
              <option
                v-for="company in companies"
                :key="company.id"
                :value="company.id"
              >
                {{ company.trade_name || company.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >Unidade<select
              v-model="queueForm.business_unit_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todas</option>
              <option v-for="unit in units" :key="unit.id" :value="unit.id">
                {{ unit.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >Tipo de solicitação<select
              v-model="queueForm.request_kind"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todos</option>
              <option value="fulfillment">Venda / Fulfillment</option>
              <option value="approval">Aprovação</option>
              <option value="change">Alteração</option>
              <option value="cancellation">Cancelamento</option>
            </select></label
          >
          <label class="text-sm"
            >Prioridade<select
              v-model="queueForm.priority"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todas</option>
              <option value="low">Baixa</option>
              <option value="normal">Normal</option>
              <option value="high">Alta</option>
              <option value="critical">Crítica</option>
            </select></label
          >
          <label class="text-sm"
            >Produto<select
              v-model="queueForm.product_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todos</option>
              <option
                v-for="product in products"
                :key="product.id"
                :value="product.id"
              >
                {{ product.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >Equipe<select
              v-model="queueForm.team_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Sem equipe fixa</option>
              <option v-for="team in teams" :key="team.id" :value="team.id">
                {{ team.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >Responsável preferencial<select
              v-model="queueForm.user_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Definido pela estratégia</option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">
                {{ agent.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >Distribuição<select
              v-model="queueForm.assignment_strategy"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="manual">Manual</option>
              <option value="round_robin">Round Robin</option>
              <option value="least_load">Menor carga</option>
              <option value="specialty">Especialidade / regra</option>
            </select></label
          >
          <label class="text-sm"
            >Especialidade<input
              v-model="queueForm.specialty"
              class="mt-1 w-full rounded-lg border p-2"
              placeholder="Implantação, financeiro..."
          /></label>
          <button
            class="rounded-lg bg-emerald-600 px-4 py-2 font-semibold text-white sm:col-span-2"
            :disabled="saving"
          >
            Criar fila
          </button>
        </form>
        <div class="mt-5 overflow-x-auto">
          <table class="w-full min-w-[650px] text-sm">
            <thead>
              <tr class="border-b text-left text-xs uppercase text-n-slate-11">
                <th class="p-2">Fila</th>
                <th>Empresa</th>
                <th>Unidade</th>
                <th>Equipe</th>
                <th>Estratégia</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="queue in queues" :key="queue.id" class="border-b">
                <td class="p-3">
                  <b>{{ queue.name }}</b>
                  <p class="text-xs text-n-slate-11">{{ queue.code }}</p>
                </td>
                <td>{{ queue.operating_company?.name || 'Todas' }}</td>
                <td>{{ queue.business_unit?.name || 'Todas' }}</td>
                <td>{{ queue.team?.name || '—' }}</td>
                <td>{{ queue.assignment_strategy }}</td>
                <td>{{ queue.active ? 'Ativa' : 'Inativa' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </article>

      <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
        <h3 class="font-bold">Políticas de SLA</h3>
        <p class="mt-1 text-sm text-n-slate-11">
          Primeira ação, etapa e total, com calendário de atendimento e pausa
          configurável.
        </p>
        <form
          class="mt-4 grid gap-3 sm:grid-cols-2"
          @submit.prevent="savePolicy"
        >
          <label class="text-sm sm:col-span-2"
            >Nome<input
              v-model="policyForm.name"
              required
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="text-sm"
            >Fila<select
              v-model="policyForm.operations_queue_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Qualquer fila</option>
              <option v-for="queue in queues" :key="queue.id" :value="queue.id">
                {{ queue.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >Tipo<select
              v-model="policyForm.request_kind"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todos</option>
              <option value="fulfillment">Implantação</option>
              <option value="approval">Aprovação</option>
              <option value="change">Alteração</option>
              <option value="cancellation">Cancelamento</option>
            </select></label
          >
          <label class="text-sm"
            >Produto<select
              v-model="policyForm.product_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todos</option>
              <option
                v-for="product in products"
                :key="product.id"
                :value="product.id"
              >
                {{ product.name }}
              </option>
            </select></label
          >
          <label class="text-sm"
            >Prioridade<select
              v-model="policyForm.priority"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Todas</option>
              <option value="low">Baixa</option>
              <option value="normal">Normal</option>
              <option value="high">Alta</option>
              <option value="critical">Crítica</option>
            </select></label
          >
          <label class="text-sm"
            >1ª ação (min)<input
              v-model="policyForm.first_action_minutes"
              type="number"
              min="1"
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="text-sm"
            >Etapa (min)<input
              v-model="policyForm.stage_minutes"
              type="number"
              min="1"
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="text-sm"
            >Total (min)<input
              v-model="policyForm.total_minutes"
              type="number"
              min="1"
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="flex items-center gap-2 text-sm sm:col-span-2"
            ><input v-model="policyForm.business_enabled" type="checkbox" />
            Usar calendário de atendimento</label
          >
          <label class="text-sm"
            >Início<input
              v-model="policyForm.business_start"
              type="time"
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="text-sm"
            >Fim<input
              v-model="policyForm.business_end"
              type="time"
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="text-sm"
            >Dias úteis<input
              v-model="policyForm.weekdays"
              class="mt-1 w-full rounded-lg border p-2"
              placeholder="1,2,3,4,5"
          /></label>
          <label class="text-sm"
            >Feriados<input
              v-model="policyForm.holidays"
              class="mt-1 w-full rounded-lg border p-2"
              placeholder="2026-12-25,2027-01-01"
          /></label>
          <label class="text-sm"
            >Status que pausam SLA<input
              v-model="policyForm.pause_statuses"
              class="mt-1 w-full rounded-lg border p-2"
          /></label>
          <label class="text-sm"
            >Alertas (%)<input
              v-model="policyForm.thresholds"
              class="mt-1 w-full rounded-lg border p-2" /></label
          ><label class="text-sm sm:col-span-2"
            >Escalonar após violação para<select
              v-model="policyForm.escalation_user_id"
              class="mt-1 w-full rounded-lg border p-2"
            >
              <option value="">Sem reatribuição automática</option>
              <option v-for="agent in agents" :key="agent.id" :value="agent.id">
                {{ agent.name }}
              </option>
            </select></label
          >
          <button
            class="rounded-lg bg-blue-600 px-4 py-2 font-semibold text-white sm:col-span-2"
            :disabled="saving"
          >
            Criar política
          </button>
        </form>
        <div class="mt-5 space-y-2">
          <div
            v-for="policy in policies"
            :key="policy.id"
            class="rounded-xl border p-3 text-sm"
          >
            <div class="flex justify-between gap-3">
              <b>{{ policy.name }}</b
              ><span>{{ policy.active ? 'Ativa' : 'Inativa' }}</span>
            </div>
            <p class="mt-1 text-n-slate-11">
              {{ policy.queue?.name || 'Qualquer fila' }} · 1ª ação
              {{ policy.first_action_minutes || '—' }} min · etapa
              {{ policy.stage_minutes || '—' }} min · total
              {{ policy.total_minutes || '—' }} min
            </p>
          </div>
        </div>
      </article>
    </div>

    <article class="rounded-2xl border bg-n-solid-2 p-5 shadow-sm">
      <h3 class="font-bold">Monitoramento por fila</h3>
      <p class="mt-1 text-sm text-n-slate-11">
        Volume e saúde do SLA calculados a partir das Solicitações vinculadas.
      </p>
      <div class="mt-4 overflow-x-auto">
        <table class="w-full min-w-[760px] text-sm">
          <thead>
            <tr class="border-b text-left text-xs uppercase text-n-slate-11">
              <th class="p-2">Fila</th>
              <th>Volume</th>
              <th>No prazo</th>
              <th>50%</th>
              <th>Atenção</th>
              <th>Crítico</th>
              <th>Vencido</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in queueStats" :key="row.id" class="border-b">
              <td class="p-3 font-semibold">{{ row.name }}</td>
              <td>{{ row.total }}</td>
              <td class="text-emerald-700">{{ row.within }}</td>
              <td class="text-yellow-700">{{ row.watch }}</td>
              <td class="text-amber-700">{{ row.attention }}</td>
              <td class="text-orange-700">{{ row.critical }}</td>
              <td class="font-semibold text-red-700">{{ row.overdue }}</td>
            </tr>
          </tbody>
        </table>
        <p
          v-if="!queueStats.length"
          class="py-8 text-center text-sm text-n-slate-11"
        >
          Nenhuma Solicitação ativa para monitorar.
        </p>
      </div>
    </article>
  </div>
</template>
