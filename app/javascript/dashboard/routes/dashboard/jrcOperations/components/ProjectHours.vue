<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { request, errorMessage, dateInput, formatDate } from '../api';
const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed']);
const { accountId, projectText } = useProjects();
const rows = ref([]);
const page = ref(1);
const total = ref(0);
const error = ref('');
const busy = ref(false);
const success = ref('');
const costs = reactive({});
const loading = ref(false);
const base = `projects/projects/${props.project.id}`;
const form = reactive({
  task_id: '',
  minutes: 60,
  worked_on: dateInput(new Date()),
  notes: '',
});
const budget = ref(props.project.budget || null);
const budgetForm = reactive({
  planned: (props.project.budget?.planned_cents || 0) / 100,
  committed: (props.project.budget?.committed_cents || 0) / 100,
});
const can = name => props.project.capabilities.includes(`projects.${name}`);
const canLogHours = computed(
  () =>
    can('time_entry.create') &&
    !['completed', 'canceled'].includes(props.project.status)
);
const financial = computed(() => can('budget.view'));
const statuses = {
  submitted: 'Enviado',
  approved: 'Aprovado',
  rejected: 'Rejeitado',
};
const money = cents =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    Number(cents || 0) / 100
  );
async function load() {
  loading.value = true;
  error.value = '';
  try {
    const result = await request(accountId.value, `${base}/time_entries`, {
      params: { page: page.value, per_page: 25 },
    });
    rows.value = result.data;
    total.value = result.meta.total;
    for (const row of rows.value)
      costs[row.id] = (row.hourly_cost_cents || 0) / 100;
    if (financial.value) {
      budget.value = (await request(accountId.value, `${base}/budget`)).data;
      budgetForm.planned = budget.value.planned_cents / 100;
      budgetForm.committed = budget.value.committed_cents / 100;
    }
    return true;
  } catch (err) {
    error.value = errorMessage(err);
    return false;
  } finally {
    loading.value = false;
  }
}

onMounted(load);
async function save() {
  if (busy.value || !canLogHours.value) return;
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    await request(accountId.value, `${base}/time_entries`, {
      method: 'post',
      data: { time_entry: { ...form, task_id: form.task_id || null } },
    });
    form.notes = '';
    if (await load())
      success.value = 'Horas registradas para sua analise e aprovacao.';
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function review(row, status) {
  if (busy.value || !can('time_entry.manage')) return;
  busy.value = true;
  error.value = '';
  try {
    await request(accountId.value, `${base}/time_entries/${row.id}`, {
      method: 'patch',
      data: {
        time_entry: {
          status,
          ...(can('budget.manage')
            ? { hourly_cost_cents: Math.round(Number(costs[row.id]) * 100) }
            : {}),
        },
      },
    });
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function saveBudget() {
  if (busy.value || !can('budget.manage')) return;
  busy.value = true;
  error.value = '';
  try {
    budget.value = (
      await request(accountId.value, `${base}/budget`, {
        method: 'patch',
        data: {
          budget: {
            currency: 'BRL',
            planned_cents: Math.round(Number(budgetForm.planned) * 100),
            committed_cents: Math.round(Number(budgetForm.committed) * 100),
          },
        },
      })
    ).data;
    success.value = 'Orcamento atualizado.';
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
function navigatePage(delta) {
  if (loading.value || busy.value) return;
  page.value += delta;
  load();
}
</script>

<template>
  <section class="flex flex-col gap-4">
    <div
      v-if="error"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
      role="alert"
    >
      {{ error }}
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
        :disabled="busy || loading"
        @click="load"
      >
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <p v-if="loading" role="status">
      {{ projectText('HOURS_LOADING', 'Carregando apontamentos...') }}
    </p>
    <div
      v-if="success"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3 info"
      role="status"
    >
      {{ success }}
    </div>
    <div v-if="project.overview" class="grid grid-cols-2 xl:grid-cols-4 gap-3">
      <div
        class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
      >
        <strong>{{
            (project.overview.estimated_minutes / 60).toLocaleString('pt-BR', {
              maximumFractionDigits: 2,
            })
          }}
          h</strong><span>{{ projectText('ESTIMATED_HOURS', 'Horas previstas') }}</span>
      </div>
      <div
        class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
      >
        <strong>{{
            (project.overview.worked_minutes / 60).toLocaleString('pt-BR', {
              maximumFractionDigits: 2,
            })
          }}
          h</strong><span>{{
          projectText(
            'WORKED_HOURS',
            'Horas registradas (enviadas ou aprovadas)'
          )
        }}</span>
      </div>
      <div
        class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
      >
        <strong>{{
            (project.overview.approved_minutes / 60).toLocaleString('pt-BR', {
              maximumFractionDigits: 2,
            })
          }}
          h</strong><span>{{ projectText('APPROVED_HOURS', 'Horas aprovadas') }}</span>
      </div>
    </div>
    <section
      v-if="financial && budget"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
    >
      <h3>Orcamento da entrega</h3>
      <div class="grid grid-cols-2 xl:grid-cols-4 gap-3">
        <div
          class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
        >
          <strong class="text-2xl">{{ money(budget.planned_cents) }}</strong><span>Previsto</span>
        </div>
        <div
          class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
        >
          <strong class="text-2xl">{{ money(budget.committed_cents) }}</strong><span>Comprometido (informado)</span>
        </div>
        <div
          class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
        >
          <strong class="text-2xl">{{ money(budget.actual_cents) }}</strong><span>Custo de horas aprovadas</span>
        </div>
        <div
          class="flex flex-col gap-1 [&_strong]:text-2xl [&_strong]:font-semibold [&_span]:text-xs [&_span]:text-n-slate-11"
        >
          <strong class="text-2xl">{{ money(budget.remaining_cents) }}</strong><span>Saldo previsto menos realizado</span>
        </div>
      </div>
      <p class="text-sm text-n-slate-11">
        O realizado considera somente horas aprovadas com custo/hora informado.
        Nao representa despesas externas, faturamento ou lucro.
      </p>
      <form
        v-if="can('budget.manage')"
        class="flex flex-wrap items-center gap-3"
        @submit.prevent="saveBudget"
      >
        <label class="flex flex-col gap-1 min-w-0"><span>Previsto (R$)</span><input
            v-model.number="budgetForm.planned"
            type="number"
            min="0"
            step="0.01"
            required /></label><label class="flex flex-col gap-1 min-w-0"><span>Comprometido (R$)</span><input
            v-model.number="budgetForm.committed"
            type="number"
            min="0"
            step="0.01"
            required /></label><button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          :disabled="busy || loading"
        >
          Salvar orcamento
        </button>
      </form>
    </section>
    <p
      v-if="['completed', 'canceled'].includes(project.status)"
      class="text-sm text-n-slate-11"
    >
      {{
        projectText(
          'CLOSED_TIME',
          'Reabra o projeto para registrar novas horas.'
        )
      }}
    </p>
    <form
      v-if="canLogHours"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
      @submit.prevent="save"
    >
      <h3>Registrar minhas horas</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <label class="flex flex-col gap-1 min-w-0"><span>Tarefa (opcional)</span><select v-model="form.task_id">
            <option value="">Trabalho geral do projeto</option>
            <option v-for="task in tasks" :key="task.id" :value="task.id">
              {{ task.title }}
            </option>
          </select></label><label class="flex flex-col gap-1 min-w-0"><span>Data</span><input v-model="form.worked_on" type="date" required /></label><label class="flex flex-col gap-1 min-w-0"><span>Minutos trabalhados</span><input
            v-model.number="form.minutes"
            type="number"
            min="1"
            max="1440"
            step="1"
            required /></label><label class="flex flex-col gap-1 min-w-0"><span>Observacao</span><input
v-model="form.notes" maxlength="2000"
        /></label>
      </div>
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 bg-n-blue-9 text-white"
        :disabled="busy || loading"
      >
        Registrar horas
      </button>
    </form>
    <div class="overflow-x-auto">
      <table
        class="w-full text-sm text-left [&_th]:p-3 [&_td]:p-3 [&_td]:border-t [&_td]:border-n-weak"
      >
        <thead>
          <tr>
            <th>Data</th>
            <th>Pessoa</th>
            <th>Minutos</th>
            <th>Situacao</th>
            <th v-if="financial">Custo/hora (R$)</th>
            <th v-if="can('time_entry.manage')">Revisao</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.id">
            <td>{{ formatDate(row.worked_on) }}</td>
            <td>{{ row.user?.name }}</td>
            <td>{{ row.minutes }}</td>
            <td>{{ statuses[row.status] }}</td>
            <td v-if="financial">
              <input
                v-if="can('budget.manage')"
                v-model.number="costs[row.id]"
                class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[110px]"
                type="number"
                min="0"
                step="0.01"
                aria-label="Custo por hora em reais"
              /><span v-else>{{ money(row.hourly_cost_cents) }}</span>
            </td>
            <td v-if="can('time_entry.manage')">
              <button
                class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
                :disabled="busy || loading"
                @click="review(row, 'approved')"
              >
                {{ row.status === 'approved' ? 'Atualizar custo' : 'Aprovar' }}
              </button>
              <button
                class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs text-n-ruby-11"
                :disabled="busy || loading"
                @click="review(row, 'rejected')"
              >
                Rejeitar
              </button>
            </td>
          </tr>
          <tr v-if="!loading && !error && !rows.length">
            <td colspan="6" class="p-6 text-center text-n-slate-11">
              {{ projectText('NO_TIME_ENTRIES', 'Nenhum apontamento.') }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="total > 25" class="flex justify-end items-center gap-3 pt-4">
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        :disabled="page <= 1 || busy || loading"
        @click="navigatePage(-1)"
      >
        Anterior</button><span>Pagina {{ page }}</span><button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        :disabled="page * 25 >= total || busy || loading"
        @click="navigatePage(1)"
      >
        Proxima
      </button>
    </div>
  </section>
</template>
