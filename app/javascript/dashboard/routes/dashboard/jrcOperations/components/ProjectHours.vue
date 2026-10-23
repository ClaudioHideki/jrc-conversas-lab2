<script setup>
import { ref, reactive, computed, watch, nextTick } from 'vue';
import { useProjects } from '../../jrcProjects/useProjects';
import { request, allPages, errorMessage, dateInput, formatDate } from '../api';

const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed']);
const { accountId, projectText } = useProjects();
const rows = ref([]);
const page = ref(1);
const pageSize = 15;
const error = ref('');
const busy = ref(false);
const success = ref('');
const costs = reactive({});
const savedCosts = new Map();
const loading = ref(false);
const tab = ref('entries');
const query = ref('');
const personFilter = ref('');
const taskFilter = ref('');
const dateFrom = ref('');
const dateTo = ref('');
const budgetEditing = ref(false);
const duration = ref('01:00');
const editingEntry = ref(null);
const entryForm = ref(null);
const base = computed(() => `projects/projects/${props.project.id}`);
const form = reactive({ task_id: '', worked_on: dateInput(), notes: '' });
const budget = ref(props.project.budget || null);
const budgetForm = reactive({ planned: 0, committed: 0 });
const can = name => props.project.capabilities.includes(`projects.${name}`);
const canLogHours = computed(
  () =>
    can('time_entry.create') &&
    !['completed', 'canceled'].includes(props.project.status)
);
const financial = computed(() => can('budget.view'));
const statuses = computed(() => ({
  submitted: projectText('TIME_SUBMITTED', 'Enviado'),
  approved: projectText('TIME_APPROVED', 'Aprovado'),
  rejected: projectText('TIME_REJECTED', 'Rejeitado'),
}));
const tabs = computed(() => [
  ['entries', projectText('TIME_ENTRIES', 'Apontamentos')],
  ['submitted', projectText('TIME_PENDING', 'Pendentes de aprovação')],
  ['approved', projectText('TIME_APPROVED_PLURAL', 'Aprovados')],
  ['rejected', projectText('TIME_REJECTED_PLURAL', 'Reprovados')],
  ['report', projectText('TIME_REPORT', 'Resumo por pessoa')],
]);
const money = cents =>
  new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: budget.value?.currency || 'BRL',
  }).format(Number(cents || 0) / 100);
const hours = minutes =>
  `${Math.floor(Number(minutes || 0) / 60)}:${String(Number(minutes || 0) % 60).padStart(2, '0')}`;
const decimalHours = minutes =>
  (Number(minutes || 0) / 60).toLocaleString('pt-BR', {
    maximumFractionDigits: 2,
  });
const estimated = computed(() =>
  Number(props.project.overview?.estimated_minutes || 0)
);
const estimatedConfigured = computed(
  () => props.project.overview?.estimated_configured ?? estimated.value > 0
);
const registered = computed(() =>
  Number(props.project.overview?.worked_minutes || 0)
);
const approved = computed(() =>
  Number(props.project.overview?.approved_minutes || 0)
);
const metrics = computed(() => [
  {
    label: projectText('ESTIMATED_HOURS', 'Horas previstas'),
    value: estimatedConfigured.value
      ? `${decimalHours(estimated.value)} h`
      : projectText('NOT_CONFIGURED', 'Não configurado'),
    icon: 'i-lucide-clock-3',
    color: 'text-n-blue-11 bg-n-blue-2',
    minutes: estimated.value,
  },
  {
    label: projectText('TIME_REGISTERED', 'Horas registradas'),
    value: `${decimalHours(registered.value)} h`,
    icon: 'i-lucide-play',
    color: 'text-n-teal-11 bg-n-teal-2',
    minutes: registered.value,
  },
  {
    label: projectText('APPROVED_HOURS', 'Horas aprovadas'),
    value: `${decimalHours(approved.value)} h`,
    icon: 'i-lucide-circle-check',
    color: 'text-n-blue-11 bg-n-blue-2',
    minutes: approved.value,
  },
  {
    label: projectText('REMAINING_HOURS', 'Horas restantes previstas'),
    value: estimatedConfigured.value
      ? `${decimalHours(Math.max(0, estimated.value - registered.value))} h`
      : projectText('NOT_CONFIGURED', 'Não configurado'),
    icon: 'i-lucide-hourglass',
    color: 'text-n-amber-11 bg-n-amber-2',
    minutes: Math.max(0, estimated.value - registered.value),
  },
]);
const budgetMetrics = computed(() => [
  {
    key: 'planned_cents',
    label: projectText('BUDGET_PLANNED', 'Previsto'),
    icon: 'i-lucide-badge-dollar-sign',
    color: 'text-n-blue-11 bg-n-blue-2',
  },
  {
    key: 'committed_cents',
    label: projectText('BUDGET_COMMITTED', 'Comprometido informado'),
    icon: 'i-lucide-wallet',
    color: 'text-n-iris-11 bg-n-iris-2',
  },
  {
    key: 'actual_cents',
    label: projectText('BUDGET_ACTUAL', 'Custo das horas aprovadas'),
    icon: 'i-lucide-chart-no-axes-combined',
    color: 'text-n-teal-11 bg-n-teal-2',
  },
  {
    key: 'remaining_cents',
    label: projectText('BUDGET_REMAINING', 'Saldo previsto menos realizado'),
    icon: 'i-lucide-coins',
    color: 'text-n-blue-11 bg-n-blue-2',
  },
]);
const taskTitle = id =>
  props.tasks.find(task => task.id === id)?.title ||
  (id
    ? `#${id}`
    : projectText('GENERAL_PROJECT_WORK', 'Trabalho geral do projeto'));
const people = computed(() =>
  [...new Map(rows.value.map(row => [row.user_id, row.user])).values()].filter(
    Boolean
  )
);
const filtered = computed(() => {
  const term = query.value.trim().toLocaleLowerCase();
  return rows.value.filter(
    row =>
      (!['submitted', 'approved', 'rejected'].includes(tab.value) ||
        row.status === tab.value) &&
      (!personFilter.value ||
        String(row.user_id) === String(personFilter.value)) &&
      (!taskFilter.value ||
        String(row.task_id || 'none') === String(taskFilter.value)) &&
      (!dateFrom.value || row.worked_on >= dateFrom.value) &&
      (!dateTo.value || row.worked_on <= dateTo.value) &&
      (!term ||
        `${row.user?.name || ''} ${taskTitle(row.task_id)} ${row.notes || ''}`
          .toLocaleLowerCase()
          .includes(term))
  );
});
const visible = computed(() =>
  filtered.value.slice((page.value - 1) * pageSize, page.value * pageSize)
);
const report = computed(() => {
  const values = new Map();
  filtered.value.forEach(row => {
    const person = values.get(row.user_id) || {
      id: row.user_id,
      name: row.user?.name,
      submitted: 0,
      approved: 0,
      rejected: 0,
      cost: 0,
    };
    person[row.status] += Number(row.minutes);
    if (financial.value && row.status === 'approved')
      person.cost +=
        (Number(row.minutes) * Number(row.hourly_cost_cents || 0)) / 60;
    values.set(row.user_id, person);
  });
  return [...values.values()];
});
watch([tab, query, personFilter, taskFilter, dateFrom, dateTo], () => {
  page.value = 1;
});
let generation = 0;
async function load() {
  generation += 1;
  const n = generation;
  loading.value = true;
  error.value = '';
  try {
    const [records, financialResult] = await Promise.all([
      allPages(accountId.value, `${base.value}/time_entries`),
      financial.value
        ? request(accountId.value, `${base.value}/budget`)
        : Promise.resolve(null),
    ]);
    if (n !== generation) return false;
    rows.value = records;
    records.forEach(row => {
      const cost = (row.hourly_cost_cents || 0) / 100;
      if (!savedCosts.has(row.id) || costs[row.id] === savedCosts.get(row.id))
        costs[row.id] = cost;
      savedCosts.set(row.id, cost);
    });
    budget.value = financialResult?.data || null;
    if (budget.value && !budgetEditing.value) {
      budgetForm.planned = budget.value.planned_cents / 100;
      budgetForm.committed = budget.value.committed_cents / 100;
    }
    page.value = Math.min(
      page.value,
      Math.max(1, Math.ceil(filtered.value.length / pageSize))
    );
    return true;
  } catch (err) {
    if (n === generation) error.value = errorMessage(err);
    return false;
  } finally {
    if (n === generation) loading.value = false;
  }
}
watch(
  () => [accountId.value, props.project.id],
  ([account, projectId], [previousAccount, previousProjectId] = []) => {
    if (account !== previousAccount || projectId !== previousProjectId) {
      rows.value = [];
      budget.value = null;
      page.value = 1;
      budgetEditing.value = false;
      Object.assign(budgetForm, { planned: 0, committed: 0 });
      Object.keys(costs).forEach(id => delete costs[id]);
      savedCosts.clear();
      editingEntry.value = null;
    }
    load();
  },
  { immediate: true }
);
function cancelEdit() {
  editingEntry.value = null;
  Object.assign(form, { task_id: '', worked_on: dateInput(), notes: '' });
  duration.value = '01:00';
}
async function save() {
  if (busy.value || !(editingEntry.value?.can_update || canLogHours.value))
    return;
  const match = /^(\d{1,2}):([0-5]\d)$/.exec(duration.value);
  const minutes = match ? Number(match[1]) * 60 + Number(match[2]) : 0;
  if (minutes < 1 || minutes > 1440) {
    error.value = projectText(
      'TIME_DURATION_ERROR',
      'Informe uma duração entre 00:01 e 24:00.'
    );
    return;
  }
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    const editing = Boolean(editingEntry.value);
    await request(
      accountId.value,
      `${base.value}/time_entries${editing ? `/${editingEntry.value.id}` : ''}`,
      {
        method: editing ? 'patch' : 'post',
        data: {
          time_entry: { ...form, minutes, task_id: form.task_id || null },
        },
      }
    );
    cancelEdit();
    if (await load())
      success.value = projectText(
        editing ? 'TIME_UPDATED' : 'TIME_CREATED',
        editing
          ? 'Apontamento atualizado.'
          : 'Horas enviadas para análise e aprovação.'
      );
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function editEntry(row) {
  if (busy.value || !row.can_update) return;
  editingEntry.value = row;
  Object.assign(form, {
    task_id: row.task_id || '',
    worked_on: row.worked_on,
    notes: row.notes || '',
  });
  duration.value = hours(row.minutes).padStart(5, '0');
  await nextTick(() => {
    entryForm.value?.scrollIntoView?.({ block: 'center', behavior: 'smooth' });
    entryForm.value?.querySelector('input')?.focus();
  });
}
async function removeEntry(row) {
  if (busy.value || !row.can_delete) return;
  if (
    !window.confirm(
      projectText(
        'DELETE_TIME_CONFIRM',
        'Excluir este apontamento de horas? O histórico da ação será preservado.'
      )
    )
  )
    return;
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    await request(accountId.value, `${base.value}/time_entries/${row.id}`, {
      method: 'delete',
    });
    if (editingEntry.value?.id === row.id) cancelEdit();
    savedCosts.delete(row.id);
    await load();
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function review(row, status) {
  if (busy.value || !can('time_entry.manage')) return;
  if (
    status === 'rejected' &&
    !window.confirm(
      projectText('REJECT_TIME_CONFIRM', 'Reprovar este apontamento de horas?')
    )
  )
    return;
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    await request(accountId.value, `${base.value}/time_entries/${row.id}`, {
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
    savedCosts.delete(row.id);
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
      await request(accountId.value, `${base.value}/budget`, {
        method: 'patch',
        data: {
          budget: {
            currency: budget.value?.currency || 'BRL',
            planned_cents: Math.round(Number(budgetForm.planned) * 100),
            committed_cents: Math.round(Number(budgetForm.committed) * 100),
          },
        },
      })
    ).data;
    budgetEditing.value = false;
    success.value = projectText('BUDGET_SAVED', 'Orçamento atualizado.');
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
function exportEntries() {
  if (!can('report.export') || loading.value || error.value) return;
  const columns = [
    projectText('DATE', 'Data'),
    projectText('PERSON', 'Pessoa'),
    projectText('TASK', 'Tarefa'),
    projectText('TIME_MINUTES', 'Minutos trabalhados'),
    projectText('STATUS', 'Situação'),
    projectText('TIME_NOTES', 'Observação'),
  ];
  if (financial.value) columns.push(projectText('HOURLY_COST', 'Custo/hora'));
  const records = filtered.value.map(row => {
    const values = [
      row.worked_on,
      row.user?.name,
      taskTitle(row.task_id),
      row.minutes,
      statuses.value[row.status],
      row.notes,
    ];
    if (financial.value) values.push(Number(row.hourly_cost_cents || 0) / 100);
    return values;
  });
  const csvCell = value => {
    let cell = String(value ?? '');
    if (/^(?:\s*[=+@-]|[\t\r])/.test(cell)) cell = `'${cell}`;
    return `"${cell.replace(/"/g, '""')}"`;
  };
  const blob = new Blob(
    [
      '\uFEFF',
      [columns, ...records].map(row => row.map(csvCell).join(';')).join('\r\n'),
    ],
    { type: 'text/csv;charset=utf-8' }
  );
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = `${props.project.key}-horas.csv`;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <header>
      <h2 class="m-0 text-lg font-semibold">
        {{ projectText('HOURS_BUDGET', 'Horas e orçamento') }}
      </h2>
      <p class="mb-0 mt-1 text-sm text-n-slate-11">
        {{
          projectText(
            'HOURS_SUBTITLE',
            'Acompanhe o trabalho realizado e os recursos da entrega.'
          )
        }}
      </p>
    </header>
    <div
      v-if="error"
      class="flex flex-wrap items-center gap-3 rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm"
      role="alert"
    >
      {{ error
      }}<button
        class="text-n-blue-11 underline"
        :disabled="busy || loading"
        @click="load"
      >
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <p
      v-if="success"
      class="rounded-lg border border-n-teal-6 bg-n-teal-2 p-3 text-sm text-n-teal-11"
      role="status"
    >
      {{ success }}
    </p>
    <div v-if="project.overview" class="grid grid-cols-2 gap-3 xl:grid-cols-4">
      <article
        v-for="metric in metrics"
        :key="metric.label"
        class="flex items-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
      >
        <span
          class="flex size-12 shrink-0 items-center justify-center rounded-xl"
          :class="metric.color"
          ><span
            class="pointer-events-none size-6 shrink-0"
            :class="metric.icon"
            aria-hidden="true"
        /></span>
        <div class="min-w-0 flex-1">
          <strong class="text-xl font-semibold">{{ metric.value }}</strong>
          <p class="mb-2 mt-1 text-xs text-n-slate-11">{{ metric.label }}</p>
          <progress
            v-if="estimatedConfigured"
            class="block h-1.5 w-full overflow-hidden rounded-full accent-n-blue-9 [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9"
            :value="Math.min(metric.minutes, estimated)"
            :max="Math.max(1, estimated)"
            :aria-label="metric.label"
          />
        </div>
      </article>
    </div>
    <section
      v-if="financial && budget"
      class="flex flex-col gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-4"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h3 class="m-0 text-sm font-semibold">
          {{ projectText('PROJECT_BUDGET', 'Orçamento do projeto') }}
        </h3>
        <button
          v-if="can('budget.manage')"
          class="flex items-center gap-2 rounded-lg bg-n-blue-2 px-3 py-2 text-xs font-medium text-n-blue-11"
          :aria-expanded="budgetEditing"
          @click="budgetEditing = !budgetEditing"
        >
          <span class="i-lucide-square-pen size-3" />{{
            projectText('EDIT_BUDGET', 'Editar orçamento')
          }}
        </button>
      </div>
      <div class="grid grid-cols-2 gap-4 xl:grid-cols-4">
        <div
          v-for="metric in budgetMetrics"
          :key="metric.key"
          class="flex items-center gap-3"
        >
          <span
            class="flex size-11 shrink-0 items-center justify-center rounded-lg"
            :class="metric.color"
            ><span
              class="pointer-events-none size-5 shrink-0"
              :class="metric.icon"
              aria-hidden="true"
          /></span>
          <div>
            <strong class="text-base">{{
              budget.configured || metric.key === 'actual_cents'
                ? money(budget[metric.key])
                : projectText('NOT_CONFIGURED', 'Não configurado')
            }}</strong>
            <p class="mb-0 mt-1 text-xs text-n-slate-11">{{ metric.label }}</p>
          </div>
        </div>
      </div>
      <p class="m-0 text-xs text-n-slate-11">
        {{
          projectText(
            'BUDGET_FORMULA',
            'Saldo = orçamento previsto − custo das horas aprovadas. O comprometido é informativo e não é descontado novamente.'
          )
        }}
      </p>
      <form
        v-if="budgetEditing && can('budget.manage')"
        class="flex flex-wrap items-end gap-3 border-t border-n-weak pt-4"
        @submit.prevent="saveBudget"
      >
        <label class="flex min-w-0 flex-1 flex-col gap-1 text-xs"
          ><span
            >{{ projectText('BUDGET_PLANNED', 'Previsto') }} ({{
              budget.currency
            }})</span
          ><input
            v-model.number="budgetForm.planned"
            type="number"
            min="0"
            step="0.01"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            required /></label
        ><label class="flex min-w-0 flex-1 flex-col gap-1 text-xs"
          ><span
            >{{ projectText('BUDGET_COMMITTED', 'Comprometido informado') }} ({{
              budget.currency
            }})</span
          ><input
            v-model.number="budgetForm.committed"
            type="number"
            min="0"
            step="0.01"
            class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            required /></label
        ><button
          class="rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white disabled:opacity-50"
          :disabled="busy || loading"
        >
          {{ projectText('SAVE_BUDGET', 'Salvar orçamento') }}
        </button>
      </form>
    </section>
    <p
      v-if="!canLogHours && ['completed', 'canceled'].includes(project.status)"
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
      v-if="canLogHours || editingEntry"
      ref="entryForm"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4"
      @submit.prevent="save"
    >
      <h3 class="mb-3 mt-0 text-sm font-semibold">
        {{
          editingEntry
            ? projectText('EDIT_TIME', 'Editar apontamento')
            : projectText('REGISTER_HOURS', 'Registrar horas')
        }}
      </h3>
      <div
        class="grid grid-cols-2 items-end gap-3 xl:grid-cols-[minmax(180px,1.6fr)_145px_105px_minmax(180px,1.5fr)_auto]"
      >
        <label
          class="col-span-2 flex min-w-0 flex-col gap-1 text-xs xl:col-span-1"
          ><span>{{ projectText('OPTIONAL_TASK', 'Tarefa (opcional)') }}</span
          ><select
            v-model="form.task_id"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          >
            <option value="">
              {{
                projectText('GENERAL_PROJECT_WORK', 'Trabalho geral do projeto')
              }}
            </option>
            <option v-for="task in tasks" :key="task.id" :value="task.id">
              {{ task.title }}
            </option>
          </select></label
        ><label class="flex min-w-0 flex-col gap-1 text-xs"
          ><span>{{ projectText('TIME_DATE', 'Data do trabalho') }}</span
          ><input
            v-model="form.worked_on"
            type="date"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            required /></label
        ><label class="flex min-w-0 flex-col gap-1 text-xs"
          ><span>{{ projectText('DURATION_HM', 'Horas (hh:mm)') }}</span
          ><input
            v-model="duration"
            type="text"
            inputmode="numeric"
            :placeholder="projectText('TIME_DURATION_PLACEHOLDER', '01:00')"
            maxlength="5"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            required /></label
        ><label
          class="col-span-2 flex min-w-0 flex-col gap-1 text-xs xl:col-span-1"
          ><span>{{ projectText('TIME_NOTES', 'Observação') }}</span
          ><input
            v-model="form.notes"
            maxlength="2000"
            class="w-full rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            :placeholder="
              projectText('TIME_NOTES_HINT', 'Descreva o trabalho realizado...')
            " /></label
        ><button
          class="col-span-2 rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-medium text-white disabled:opacity-50 xl:col-span-1"
          :disabled="busy || loading"
        >
          {{
            editingEntry
              ? projectText('SAVE', 'Salvar')
              : projectText('REGISTER_HOURS', 'Registrar horas')
          }}
        </button>
      </div>
      <button
        v-if="editingEntry"
        type="button"
        class="mt-3 rounded border border-n-weak px-3 py-2 text-sm"
        :disabled="busy"
        @click="cancelEdit"
      >
        {{ projectText('CANCEL', 'Cancelar') }}
      </button>
    </form>
    <div
      class="min-w-0 overflow-hidden rounded-xl border border-n-weak bg-n-solid-1"
    >
      <nav
        class="flex gap-1 overflow-x-auto border-b border-n-weak px-3"
        :aria-label="projectText('TIME_ENTRIES', 'Apontamentos')"
      >
        <button
          v-for="item in tabs"
          :key="item[0]"
          class="flex shrink-0 items-center gap-2 whitespace-nowrap border-b-2 px-3 py-3 text-sm"
          :class="
            tab === item[0]
              ? 'border-n-blue-9 font-medium text-n-blue-11'
              : 'border-transparent text-n-slate-11'
          "
          :aria-pressed="tab === item[0]"
          @click="tab = item[0]"
        >
          {{ item[1]
          }}<span
            v-if="
              item[0] === 'submitted' &&
              rows.some(row => row.status === 'submitted')
            "
            class="rounded-full bg-n-ruby-3 px-1.5 py-0.5 text-xs text-n-ruby-11"
            >{{ rows.filter(row => row.status === 'submitted').length }}</span
          >
        </button>
      </nav>
      <div class="flex flex-wrap items-center gap-2 border-b border-n-weak p-3">
        <label
          class="flex min-w-44 flex-1 items-center gap-2 rounded-lg border border-n-weak px-3"
          ><span class="i-lucide-search size-4 text-n-slate-10" /><input
            v-model="query"
            class="min-w-0 flex-1 border-0 bg-transparent py-2 text-sm outline-none"
            :placeholder="
              projectText(
                'SEARCH_TIME',
                'Pesquisar por pessoa, tarefa ou observação...'
              )
            "
            :aria-label="
              projectText(
                'SEARCH_TIME',
                'Pesquisar por pessoa, tarefa ou observação...'
              )
            " /></label
        ><select
          v-model="personFilter"
          class="w-auto rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          :aria-label="projectText('PERSON', 'Pessoa')"
        >
          <option value="">
            {{ projectText('ALL_MEMBERS', 'Todos os membros') }}
          </option>
          <option v-for="person in people" :key="person.id" :value="person.id">
            {{ person.name }}
          </option></select
        ><select
          v-model="taskFilter"
          class="max-w-56 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          :aria-label="projectText('TASK', 'Tarefa')"
        >
          <option value="">
            {{ projectText('ALL_TASKS', 'Todas as tarefas') }}
          </option>
          <option value="none">
            {{
              projectText('GENERAL_PROJECT_WORK', 'Trabalho geral do projeto')
            }}
          </option>
          <option v-for="task in tasks" :key="task.id" :value="task.id">
            {{ task.title }}
          </option></select
        ><input
          v-model="dateFrom"
          type="date"
          class="w-auto rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          :aria-label="projectText('DATE_FROM', 'Data inicial')"
        /><input
          v-model="dateTo"
          type="date"
          class="w-auto rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
          :aria-label="projectText('DATE_TO', 'Data final')"
        /><button
          v-if="can('report.export')"
          class="flex items-center gap-2 rounded-lg border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          :disabled="loading || Boolean(error) || !filtered.length"
          @click="exportEntries"
        >
          <span class="i-lucide-download size-4" />{{
            projectText('EXPORT', 'Exportar')
          }}
        </button>
      </div>
      <p v-if="loading" class="p-5 text-sm text-n-slate-11" role="status">
        {{ projectText('HOURS_LOADING', 'Carregando apontamentos...') }}
      </p>
      <div v-else-if="tab === 'report'" class="overflow-x-auto">
        <table class="w-full min-w-[650px] text-left text-sm">
          <thead class="bg-n-slate-2 text-xs text-n-slate-11">
            <tr>
              <th class="px-4 py-3">{{ projectText('PERSON', 'Pessoa') }}</th>
              <th class="px-4 py-3">
                {{ projectText('TIME_SUBMITTED', 'Enviado') }}
              </th>
              <th class="px-4 py-3">
                {{ projectText('TIME_APPROVED', 'Aprovado') }}
              </th>
              <th class="px-4 py-3">
                {{ projectText('TIME_REJECTED', 'Rejeitado') }}
              </th>
              <th v-if="financial" class="px-4 py-3">
                {{ projectText('BUDGET_ACTUAL', 'Custo das horas aprovadas') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="person in report"
              :key="person.id"
              class="border-t border-n-weak"
            >
              <td class="px-4 py-3 font-medium">{{ person.name }}</td>
              <td class="px-4 py-3">{{ hours(person.submitted) }}</td>
              <td class="px-4 py-3">{{ hours(person.approved) }}</td>
              <td class="px-4 py-3">{{ hours(person.rejected) }}</td>
              <td v-if="financial" class="px-4 py-3">
                {{ money(Math.round(person.cost)) }}
              </td>
            </tr>
            <tr v-if="!report.length">
              <td
                :colspan="financial ? 5 : 4"
                class="p-8 text-center text-n-slate-11"
              >
                {{ projectText('NO_TIME_ENTRIES', 'Nenhum apontamento.') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-else class="overflow-x-auto">
        <table class="w-full min-w-[820px] text-left text-sm">
          <thead class="bg-n-slate-2 text-xs text-n-slate-11">
            <tr>
              <th class="px-4 py-3">{{ projectText('DATE', 'Data') }}</th>
              <th class="px-4 py-3">{{ projectText('PERSON', 'Pessoa') }}</th>
              <th class="px-4 py-3">{{ projectText('TASK', 'Tarefa') }}</th>
              <th class="px-4 py-3">{{ projectText('HOURS', 'Horas') }}</th>
              <th v-if="financial" class="px-4 py-3">
                {{ projectText('HOURLY_COST', 'Custo/hora') }}
              </th>
              <th class="px-4 py-3">{{ projectText('STATUS', 'Situação') }}</th>
              <th class="px-4 py-3">
                {{ projectText('TIME_NOTES', 'Observação') }}
              </th>
              <th class="px-4 py-3 text-right">
                {{ projectText('ACTIONS', 'Ações') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="row in visible"
              :key="row.id"
              class="border-t border-n-weak hover:bg-n-slate-2/50"
            >
              <td class="whitespace-nowrap px-4 py-3 text-n-slate-11">
                {{ formatDate(row.worked_on) }}
              </td>
              <td class="px-4 py-3 font-medium">{{ row.user?.name }}</td>
              <td class="max-w-56 px-4 py-3">
                <span class="block truncate" :title="taskTitle(row.task_id)">{{
                  taskTitle(row.task_id)
                }}</span>
              </td>
              <td class="px-4 py-3 font-medium">{{ hours(row.minutes) }}</td>
              <td v-if="financial" class="px-4 py-3">
                <input
                  v-if="can('budget.manage')"
                  v-model.number="costs[row.id]"
                  type="number"
                  min="0"
                  step="0.01"
                  class="w-24 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
                  :disabled="busy"
                  :aria-label="projectText('HOURLY_COST', 'Custo/hora')"
                /><span v-else>{{ money(row.hourly_cost_cents) }}</span>
              </td>
              <td class="px-4 py-3">
                <span
                  class="whitespace-nowrap rounded-full px-2 py-1 text-xs font-medium"
                  :class="
                    row.status === 'approved'
                      ? 'bg-n-teal-2 text-n-teal-11'
                      : row.status === 'rejected'
                        ? 'bg-n-ruby-2 text-n-ruby-11'
                        : 'bg-n-amber-2 text-n-amber-11'
                  "
                  >{{ statuses[row.status] }}</span
                >
              </td>
              <td class="max-w-64 px-4 py-3 text-n-slate-11">
                <span class="block truncate" :title="row.notes">{{
                  row.notes || '—'
                }}</span>
              </td>
              <td class="px-4 py-3">
                <div class="flex flex-wrap justify-end gap-2">
                  <button
                    v-if="row.can_update"
                    type="button"
                    class="rounded-lg border border-n-weak px-2 py-1.5 text-xs"
                    :disabled="busy || loading"
                    @click="editEntry(row)"
                  >
                    {{ projectText('EDIT', 'Editar') }}
                  </button>
                  <button
                    v-if="row.can_delete"
                    type="button"
                    class="rounded-lg px-2 py-1.5 text-xs text-n-ruby-11 hover:bg-n-ruby-2"
                    :disabled="busy || loading"
                    @click="removeEntry(row)"
                  >
                    {{ projectText('DELETE', 'Excluir') }}
                  </button>
                  <button
                    v-if="
                      can('time_entry.manage') &&
                      (row.status !== 'approved' || can('budget.manage'))
                    "
                    class="whitespace-nowrap rounded-lg bg-n-blue-2 px-2 py-1.5 text-xs font-medium text-n-blue-11 disabled:opacity-50"
                    :disabled="busy || loading"
                    @click="review(row, 'approved')"
                  >
                    {{
                      row.status === 'approved'
                        ? projectText('UPDATE_COST', 'Atualizar custo')
                        : projectText('APPROVE', 'Aprovar')
                    }}</button
                  ><button
                    v-if="can('time_entry.manage') && row.status !== 'rejected'"
                    class="rounded-lg px-2 py-1.5 text-xs text-n-ruby-11 hover:bg-n-ruby-2 disabled:opacity-50"
                    :disabled="busy || loading"
                    @click="review(row, 'rejected')"
                  >
                    {{ projectText('REJECT', 'Reprovar') }}
                  </button>
                </div>
              </td>
            </tr>
            <tr v-if="!error && !visible.length">
              <td colspan="8" class="p-10 text-center text-n-slate-11">
                <span
                  class="i-lucide-clock-3 mx-auto mb-3 block size-8 text-n-slate-9"
                />{{ projectText('NO_TIME_ENTRIES', 'Nenhum apontamento.') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <footer
        v-if="!loading && tab !== 'report'"
        class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak p-3 text-sm"
      >
        <span class="text-xs text-n-slate-11"
          >{{ filtered.length }}
          {{ projectText('TIME_ENTRIES_COUNT', 'apontamentos') }}</span
        >
        <div v-if="filtered.length > pageSize" class="flex items-center gap-3">
          <button
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
            :disabled="page <= 1 || busy"
            @click="page -= 1"
          >
            {{ projectText('PREVIOUS', 'Anterior') }}</button
          ><span>{{ page }} / {{ Math.ceil(filtered.length / pageSize) }}</span
          ><button
            class="rounded-lg border border-n-weak px-3 py-2 disabled:opacity-50"
            :disabled="page * pageSize >= filtered.length || busy"
            @click="page += 1"
          >
            {{ projectText('NEXT', 'Próxima') }}
          </button>
        </div>
      </footer>
    </div>
  </section>
</template>
