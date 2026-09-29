<script setup>
import { ref, reactive, computed, watch } from 'vue';
import { useAgenda } from '../useAgenda';
import { request, errorMessage } from '../api';
import { agendaTarget, formatAgendaDue } from '../agenda';

const {
  accountId,
  userId,
  status,
  loading: statusLoading,
  error: statusError,
  refresh,
  agendaText,
} = useAgenda();
const filters = reactive({
  from: '',
  to: '',
  source: 'all',
  user_id: '',
  view: 'open',
});
const data = ref([]);
const meta = ref(null);
const error = ref('');
const loading = ref(false);
const enabled = computed(
  () => status.value?.crm_enabled || status.value?.projects_enabled
);
const sources = computed(() => [
  {
    value: 'crm',
    label: 'CRM',
    enabled: status.value?.crm_enabled,
    tone: 'bg-n-iris-3 text-n-iris-11',
  },
  {
    value: 'service_desk',
    label: agendaText(
      'SERVICE_DESK_UNAVAILABLE',
      'Service Desk (tarefas indisponíveis)'
    ),
    enabled: false,
    tone: 'bg-n-blue-3 text-n-blue-11',
  },
  {
    value: 'projects',
    label: agendaText('PROJECTS', 'Projetos'),
    enabled: status.value?.projects_enabled,
    tone: 'bg-n-teal-3 text-n-teal-11',
  },
]);
const views = computed(() => [
  ['open', agendaText('OPEN', 'Em aberto')],
  ['today', agendaText('TODAY', 'Hoje')],
  ['upcoming', agendaText('UPCOMING', 'Próximos')],
  ['overdue', agendaText('OVERDUE', 'Atrasados')],
  ['completed', agendaText('COMPLETED', 'Concluídos')],
  ['canceled', agendaText('CANCELED', 'Cancelados')],
  ['all', agendaText('ALL_STATES', 'Todos, incluindo cancelados')],
]);
const responsibleOptions = computed(() =>
  (meta.value?.users || []).filter(
    user => String(user.id) !== String(userId.value)
  )
);
const sourceLabel = entry =>
  sources.value.find(source => source.value === entry.source)?.label;
const sourceTone = entry =>
  sources.value.find(source => source.value === entry.source)?.tone;
const stateLabel = entry => {
  if (entry.completed) return agendaText('COMPLETED', 'Concluídos');
  if (entry.canceled) return agendaText('CANCELED', 'Cancelado');
  const labels = {
    backlog: ['BACKLOG', 'A fazer'],
    pending: ['PENDING', 'Pendente'],
    scheduled: ['SCHEDULED', 'Agendado'],
    in_progress: ['IN_PROGRESS', 'Em andamento'],
    review: ['REVIEW', 'Validação'],
    blocked: ['BLOCKED', 'Bloqueado'],
  };
  const [key, fallback] = labels[entry.status] || ['OPEN', 'Em aberto'];
  return agendaText(key, fallback);
};
let generation = 0;
async function load() {
  const current = ++generation;
  data.value = [];
  error.value = '';
  loading.value = false;
  if (!enabled.value) return;
  loading.value = true;
  try {
    const result = await request(accountId.value, 'operations/agenda', {
      params: { ...filters },
    });
    if (current !== generation) return;
    data.value = result.data;
    meta.value = result.meta;
    filters.from = result.meta.from;
    filters.to = result.meta.to;
  } catch (err) {
    if (current === generation) error.value = errorMessage(err);
  } finally {
    if (current === generation) loading.value = false;
  }
}
function selectView(view) {
  filters.view = view;
  // Let the server calculate the current account date, including after midnight.
  filters.from = '';
  filters.to = '';
  load();
}
watch(
  () => [
    accountId.value,
    userId.value,
    status.value?.ready,
    status.value?.crm_enabled,
    status.value?.projects_enabled,
  ],
  () => {
    meta.value = null;
    Object.assign(filters, {
      from: '',
      to: '',
      source: 'all',
      user_id: '',
      view: 'open',
    });
    load();
  },
  { immediate: true }
);
</script>

<template>
  <section class="flex flex-col gap-4">
    <p class="text-n-slate-11 text-sm">
      {{
        agendaText(
          'READ_ONLY_HELP',
          'Consulte os compromissos e abra o registro original para trabalhar nele. Cada item continua em seu módulo.'
        )
      }}
    </p>
    <div
      v-if="statusError"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
      role="alert"
    >
      {{ statusError }}
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
        @click="refresh(true)"
      >
        {{ agendaText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <p v-else-if="statusLoading && !status" role="status">
      {{ agendaText('LOADING', 'Carregando agenda...') }}
    </p>
    <p
      v-else-if="status && !enabled"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 p-6 text-center text-n-slate-11"
    >
      {{
        agendaText(
          'NO_MODULES',
          'Nenhum dos módulos da Agenda está disponível no seu acesso.'
        )
      }}
    </p>
    <template v-else-if="enabled">
      <nav
        class="flex gap-3 overflow-x-auto py-3 [&_button]:rounded-lg [&_button]:px-3 [&_button]:py-2 [&_a]:px-3 [&_a]:py-2 [&_.active]:bg-n-blue-9 [&_.active]:text-white [&_.router-link-exact-active]:text-n-blue-11"
        :aria-label="agendaText('VIEWS', 'Visualizações da agenda')"
      >
        <button
          v-for="view in views"
          :key="view[0]"
          class="rounded-lg px-3 py-2"
          :class="
            filters.view === view[0]
              ? 'bg-n-blue-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          :disabled="!meta || loading"
          @click="selectView(view[0])"
        >
          {{ view[1] }}
        </button>
      </nav>
      <form class="flex flex-wrap items-center gap-3" @submit.prevent="load">
        <label class="flex flex-col gap-1 min-w-0"><span>{{ agendaText('FROM', 'De') }}</span><input
            v-model="filters.from"
            type="date"
            required
            :disabled="loading"
        /></label>
        <label class="flex flex-col gap-1 min-w-0"><span>{{ agendaText('TO', 'Até') }}</span><input
            v-model="filters.to"
            type="date"
            :min="filters.from"
            required
            :disabled="loading"
        /></label>
        <label class="flex flex-col gap-1 min-w-0"><span>{{ agendaText('SOURCE', 'Origem') }}</span><select v-model="filters.source" :disabled="loading">
            <option value="all">
              {{ agendaText('ALL_SOURCES', 'Todas as origens') }}
            </option>
            <option
              v-for="source in sources.filter(item => item.enabled)"
              :key="source.value"
              :value="source.value"
            >
              {{ source.label }}
            </option>
          </select></label>
        <label class="flex flex-col gap-1 min-w-0"><span>{{ agendaText('RESPONSIBLE', 'Responsável') }}</span><select v-model="filters.user_id" :disabled="loading">
            <option value="">
              {{ agendaText('MY_ITEMS', 'Meus compromissos') }}
            </option>
            <option value="all">
              {{ agendaText('ACCESSIBLE_ITEMS', 'Todos no meu acesso') }}
            </option>
            <option
              v-for="user in responsibleOptions"
              :key="user.id"
              :value="user.id"
            >
              {{ user.name }}
            </option>
          </select></label>
        <button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50"
          :disabled="loading"
        >
          {{ agendaText('APPLY', 'Aplicar filtros / Atualizar') }}
        </button>
      </form>
      <p v-if="meta" class="text-sm text-n-slate-11">
        {{ agendaText('TIME_ZONE', 'Fuso horário da conta') }}:
        {{ meta.time_zone }}.
        {{
          agendaText(
            'PERIOD_HELP',
            'A visualização e os filtros respeitam o período informado. Os atrasados podem incluir horários já vencidos hoje.'
          )
        }}
      </p>
      <p v-if="loading" role="status">
        {{ agendaText('LOADING', 'Carregando agenda...') }}
      </p>
      <div
        v-else-if="error"
        class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
        role="alert"
      >
        {{ error }}
        <button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:opacity-50 text-xs"
          @click="load"
        >
          {{ agendaText('RETRY', 'Tentar novamente') }}
        </button>
      </div>
      <p
        v-else-if="!data.length"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 p-6 text-center text-n-slate-11"
      >
        {{
          filters.source !== 'all' || filters.user_id
            ? agendaText(
                'NO_FILTER_RESULTS',
                'Nenhum compromisso corresponde aos filtros no seu acesso.'
              )
            : agendaText(
                'EMPTY',
                'Nenhum compromisso nesta visualização e período.'
              )
        }}
      </p>
      <div v-else class="overflow-x-auto">
        <table
          class="w-full text-sm text-left [&_th]:p-3 [&_td]:p-3 [&_td]:border-t [&_td]:border-n-weak"
        >
          <thead>
            <tr>
              <th>{{ agendaText('DUE', 'Prazo / Data') }}</th>
              <th>{{ agendaText('SOURCE', 'Origem') }}</th>
              <th>{{ agendaText('ITEM', 'Compromisso') }}</th>
              <th>{{ agendaText('RESPONSIBLE', 'Responsável') }}</th>
              <th>{{ agendaText('STATE', 'Situação') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="entry in data" :key="entry.id">
              <td>
                <time :datetime="entry.due">{{
                  formatAgendaDue(entry, meta.time_zone)
                }}</time>
                <p
                  v-if="entry.due_type === 'date'"
                  class="text-n-slate-11 text-sm"
                >
                  {{ agendaText('DATE_ONLY', 'Somente data · sem horário') }}
                </p>
                <span
                  v-if="entry.overdue"
                  class="rounded px-2 py-1 text-xs border border-n-weak bg-n-ruby-3 text-n-ruby-11"
                  >{{ agendaText('OVERDUE', 'Atrasados') }}</span>
              </td>
              <td>
                <span
                  class="rounded px-2 py-1 text-xs border border-n-weak"
                  :class="sourceTone(entry)"
                  >{{ sourceLabel(entry) }}</span>
                <p
                  v-if="
                    entry.kind === 'crm_follow_up' ||
                    entry.activity_type === 'follow_up'
                  "
                  class="text-n-slate-11 text-sm"
                >
                  {{ agendaText('FOLLOW_UP', 'Follow-up') }}
                </p>
                <p
                  v-else-if="entry.activity_type === 'meeting'"
                  class="text-n-slate-11 text-sm"
                >
                  {{ agendaText('MEETING', 'Reunião') }}
                </p>
              </td>
              <td class="wrap">
                <RouterLink
                  class="text-n-blue-11 underline"
                  :to="agendaTarget(entry, accountId)"
                >
                  {{ entry.title }}
                </RouterLink>
                <p v-if="entry.project_key" class="text-n-slate-11 text-sm">
                  {{ entry.project_key
                  }}<span v-if="entry.parent_id">
                    · {{ agendaText('SUBTASK', 'Subtarefa') }}</span>
                </p>
                <p v-if="entry.ticket_number" class="text-n-slate-11 text-sm">
                  {{ agendaText('TICKET', 'Chamado') }} #{{
                    entry.ticket_number
                  }}
                </p>
              </td>
              <td>
                {{
                  entry.responsible ||
                  agendaText('UNASSIGNED', 'Sem responsável')
                }}
              </td>
              <td>{{ stateLabel(entry) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p class="text-n-slate-11 text-sm">
        {{
          agendaText(
            'UNDATED_HELP',
            'Itens sem prazo continuam nas listas de origem. Prazos de Projeto têm somente data; CRM exibe a data e hora cadastradas.'
          )
        }}
      </p>
    </template>
  </section>
</template>
