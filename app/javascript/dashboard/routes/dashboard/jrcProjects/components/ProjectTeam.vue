<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useProjects } from '../useProjects';
import {
  errorMessage,
  request,
  routeTo,
  formatDate,
} from '../../jrcOperations/api';
import { projectTaskStatuses } from '../taskBoard';
import OpsModal from '../../jrcOperations/components/OpsModal.vue';

const props = defineProps({
  project: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
});
const emit = defineEmits(['changed']);
const { accountId, userId, projectText } = useProjects();
const search = ref('');
const roleFilter = ref('');
const availabilityFilter = ref('');
const page = ref(1);
const selectedId = ref(null);
const panelTab = ref('overview');
const modal = ref(false);
const editing = ref(null);
const busy = ref(false);
const loadingOptions = ref(false);
const error = ref('');
const success = ref('');
const users = ref([]);
const form = reactive({ user_id: '', role: 'member', allocation_percent: 100 });
const members = computed(() => props.project.members || []);
const canManage = computed(() =>
  props.project.capabilities?.includes('projects.member.manage')
);
const selected = computed(() =>
  members.value.find(member => member.id === selectedId.value)
);
const roles = computed(() => ({
  owner: projectText('TEAM_ROLE_OWNER', 'Proprietário'),
  manager: projectText('TEAM_ROLE_MANAGER', 'Gerente'),
  member: projectText('TEAM_ROLE_MEMBER', 'Membro'),
  contributor: projectText('TEAM_ROLE_CONTRIBUTOR', 'Colaborador'),
  viewer: projectText('TEAM_ROLE_VIEWER', 'Observador'),
}));
const editableRoles = computed(() =>
  Object.entries(roles.value).filter(([key]) => key !== 'owner')
);
const roleDescriptions = computed(() => ({
  owner: projectText(
    'TEAM_OWNER_HELP',
    'Responsável pelo projeto, pela equipe e pelas configurações autorizadas.'
  ),
  manager: projectText(
    'TEAM_MANAGER_HELP',
    'Gerencia tarefas, planejamento e participantes conforme as permissões da conta.'
  ),
  member: projectText(
    'TEAM_MEMBER_HELP',
    'Cria e atualiza tarefas e registra horas conforme as permissões da conta.'
  ),
  contributor: projectText(
    'TEAM_CONTRIBUTOR_HELP',
    'Atualiza tarefas atribuídas a ele ou criadas por ele e registra horas.'
  ),
  viewer: projectText(
    'TEAM_VIEWER_HELP',
    'Consulta o projeto e suas tarefas, sem permissão de edição.'
  ),
}));
const availableUsers = computed(() =>
  users.value.filter(
    user => !members.value.some(member => member.user_id === user.id)
  )
);
const assignedTasks = computed(
  () => props.tasks.filter(task => task.assignee_id).length
);
const capacity = computed(() => {
  if (
    !members.value.length ||
    members.value.some(member => member.total_allocation_percent == null)
  )
    return null;
  return Math.round(
    members.value.reduce(
      (sum, member) => sum + Number(member.total_allocation_percent),
      0
    ) / members.value.length
  );
});
const filteredMembers = computed(() => {
  const query = search.value.trim().toLocaleLowerCase();
  return members.value.filter(member => {
    if (
      query &&
      !`${member.user?.name || ''} ${member.user?.email || ''}`
        .toLocaleLowerCase()
        .includes(query)
    )
      return false;
    if (roleFilter.value && member.role !== roleFilter.value) return false;
    if (availabilityFilter.value === 'overallocated')
      return member.overallocated === true;
    if (availabilityFilter.value === 'available')
      return Number(member.available_percent) > 0;
    if (availabilityFilter.value === 'full')
      return member.available_percent === 0 && !member.overallocated;
    return true;
  });
});
const visibleMembers = computed(() =>
  filteredMembers.value.slice((page.value - 1) * 25, page.value * 25)
);
watch(
  () => filteredMembers.value.length,
  count => {
    page.value = Math.min(page.value, Math.max(1, Math.ceil(count / 25)));
  }
);
const memberTasks = computed(() =>
  props.tasks.filter(task => task.assignee_id === selected.value?.user_id)
);
const selectedCompleted = computed(
  () => memberTasks.value.filter(task => task.status === 'completed').length
);
const selectedWorked = computed(() =>
  memberTasks.value.reduce(
    (sum, task) => sum + Number(task.worked_minutes || 0),
    0
  )
);
const filtersKey = computed(
  () =>
    `jrc:projects:team:${accountId.value}:${userId.value}:${props.project.id}`
);
watch(
  filtersKey,
  () => {
    let filters = {};
    try {
      filters = JSON.parse(
        window.localStorage.getItem(filtersKey.value) || '{}'
      );
    } catch {
      filters = {};
    }
    search.value = filters.search || '';
    roleFilter.value = filters.role || '';
    availabilityFilter.value = filters.availability || '';
    selectedId.value = null;
    page.value = 1;
  },
  { immediate: true }
);
watch([search, roleFilter, availabilityFilter], () => {
  page.value = 1;
  try {
    window.localStorage.setItem(
      filtersKey.value,
      JSON.stringify({
        search: search.value,
        role: roleFilter.value,
        availability: availabilityFilter.value,
      })
    );
  } catch {
    // Filtering remains available when browser storage is disabled.
  }
});
watch(
  () => props.project.id,
  () => {
    modal.value = false;
    editing.value = null;
    error.value = '';
    success.value = '';
  }
);
function isOwner(member) {
  return member?.role === 'owner' || member?.user_id === props.project.owner_id;
}
function initials(name) {
  return String(name || '')
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map(part => part[0])
    .join('')
    .toUpperCase();
}
function openDetails(member) {
  selectedId.value = member.id;
  panelTab.value = 'overview';
}
function memberCount(member, status) {
  if (!status && member.assigned_tasks_count != null)
    return member.assigned_tasks_count;
  return props.tasks.filter(
    task =>
      task.assignee_id === member.user_id && (!status || task.status === status)
  ).length;
}
function availability(member) {
  if (member.total_allocation_percent == null)
    return projectText('TEAM_CAPACITY_UNAVAILABLE', 'Não informada');
  if (member.overallocated)
    return projectText('TEAM_OVERALLOCATED', 'Sobrealocado');
  if (member.available_percent === 0)
    return projectText('TEAM_FULL', 'Totalmente alocado');
  return projectText('TEAM_AVAILABLE', 'Disponível');
}
async function openEditor(member = null) {
  if (!canManage.value || isOwner(member)) return;
  editing.value = member;
  Object.assign(form, {
    user_id: member?.user_id || '',
    role: member?.role || 'member',
    allocation_percent: member?.allocation_percent ?? 100,
  });
  error.value = '';
  success.value = '';
  modal.value = true;
  if (member) return;
  loadingOptions.value = true;
  try {
    const result = await request(accountId.value, 'operations/options');
    users.value = result.data.users || [];
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    loadingOptions.value = false;
  }
}
async function save() {
  if (busy.value || !canManage.value || isOwner(editing.value)) return;
  busy.value = true;
  error.value = '';
  try {
    const endpoint = `projects/projects/${props.project.id}/members`;
    await request(
      accountId.value,
      editing.value ? `${endpoint}/${editing.value.id}` : endpoint,
      {
        method: editing.value ? 'patch' : 'post',
        data: {
          record: {
            user_id: Number(form.user_id),
            role: form.role,
            allocation_percent: Number(form.allocation_percent),
          },
        },
      }
    );
    modal.value = false;
    success.value = projectText('TEAM_SAVED', 'Participante salvo.');
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
async function remove(member) {
  if (busy.value || !canManage.value || isOwner(member)) return;
  if (
    !window.confirm(
      projectText(
        'TEAM_REMOVE_CONFIRM',
        'Remover este participante? Reatribua as tarefas dele antes de continuar.'
      )
    )
  )
    return;
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    await request(
      accountId.value,
      `projects/projects/${props.project.id}/members/${member.id}`,
      { method: 'delete' }
    );
    if (selectedId.value === member.id) selectedId.value = null;
    success.value = projectText('TEAM_REMOVED', 'Participante removido.');
    emit('changed');
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    busy.value = false;
  }
}
function taskRoute(task) {
  return {
    ...routeTo('jrc_projects_detail', accountId.value, {
      projectId: props.project.id,
    }),
    query: { taskId: task.id },
  };
}
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <div class="grid grid-cols-1 gap-3 md:grid-cols-3">
      <article
        class="flex items-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
      >
        <span
          class="flex size-12 items-center justify-center rounded-xl bg-n-teal-3 text-n-teal-11"
          aria-hidden="true"
          ><span class="i-lucide-users size-6"
        /></span>
        <div>
          <strong class="block text-2xl font-semibold">{{
            members.length
          }}</strong>
          <p class="text-sm text-n-slate-11">
            {{ projectText('TEAM_MEMBERS', 'Integrantes da equipe') }}
          </p>
        </div>
      </article>
      <article
        class="flex items-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
      >
        <span
          class="flex size-12 items-center justify-center rounded-xl bg-n-teal-3 text-n-teal-11"
          aria-hidden="true"
          ><span class="i-lucide-list-checks size-6"
        /></span>
        <div>
          <strong class="block text-2xl font-semibold">{{
            assignedTasks
          }}</strong>
          <p class="text-sm text-n-slate-11">
            {{ projectText('TEAM_ASSIGNED_TASKS', 'Tarefas atribuídas') }}
          </p>
          <span class="text-xs text-n-slate-11">{{
            projectText('TEAM_IN_THIS_PROJECT', 'Neste projeto')
          }}</span>
        </div>
      </article>
      <article
        class="flex items-center gap-4 rounded-xl border border-n-weak bg-n-solid-1 p-5"
      >
        <span
          class="flex size-12 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
          aria-hidden="true"
          ><span class="i-lucide-gauge size-6"
        /></span>
        <div class="min-w-0 flex-1">
          <strong
            class="block font-semibold"
            :class="capacity === null ? 'text-sm' : 'text-2xl'"
            >{{
              capacity === null
                ? projectText('NOT_CONFIGURED', 'Não configurado')
                : `${capacity}%`
            }}</strong
          >
          <p class="text-sm text-n-slate-11">
            {{ projectText('TEAM_USED_CAPACITY', 'Capacidade utilizada') }}
          </p>
          <span class="text-xs text-n-slate-11">{{
            projectText(
              'TEAM_CAPACITY_HINT',
              'Média nos projetos planejados e em execução'
            )
          }}</span>
        </div>
      </article>
    </div>

    <p
      v-if="error && !modal"
      role="alert"
      class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm"
    >
      {{ error }}
    </p>
    <p
      v-if="success"
      role="status"
      class="rounded-lg border border-n-teal-7 bg-n-teal-2 p-3 text-sm"
    >
      {{ success }}
    </p>
    <div
      class="grid min-w-0 gap-4"
      :class="selected ? '2xl:grid-cols-[minmax(0,1fr)_320px]' : 'grid-cols-1'"
    >
      <div class="min-w-0 rounded-xl border border-n-weak bg-n-solid-1">
        <header
          class="flex flex-wrap items-center gap-3 border-b border-n-weak p-4"
        >
          <label class="relative min-w-[180px] flex-1"
            ><span
              class="i-lucide-search pointer-events-none absolute left-3 top-3 size-4 text-n-slate-10"
              aria-hidden="true" /><input
              v-model="search"
              class="m-0 w-full rounded-lg border border-n-weak bg-n-solid-1 py-2 pl-9 pr-3 text-sm"
              :placeholder="
                projectText('TEAM_SEARCH', 'Pesquisar participante...')
              "
              :aria-label="
                projectText('TEAM_SEARCH', 'Pesquisar participante...')
              "
          /></label>
          <select
            v-model="roleFilter"
            class="m-0 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            :aria-label="projectText('TEAM_ROLE', 'Papel')"
          >
            <option value="">
              {{ projectText('TEAM_ALL_ROLES', 'Todos os papéis') }}
            </option>
            <option v-for="(label, key) in roles" :key="key" :value="key">
              {{ label }}
            </option>
          </select>
          <select
            v-model="availabilityFilter"
            class="m-0 rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
            :aria-label="projectText('TEAM_AVAILABILITY', 'Disponibilidade')"
          >
            <option value="">
              {{
                projectText(
                  'TEAM_ALL_AVAILABILITY',
                  'Todas as disponibilidades'
                )
              }}
            </option>
            <option value="available">
              {{ projectText('TEAM_AVAILABLE', 'Disponível') }}
            </option>
            <option value="full">
              {{ projectText('TEAM_FULL', 'Totalmente alocado') }}
            </option>
            <option value="overallocated">
              {{ projectText('TEAM_OVERALLOCATED', 'Sobrealocado') }}
            </option>
          </select>
          <button
            v-if="canManage"
            class="flex items-center gap-2 rounded-lg bg-n-blue-9 px-3 py-2 text-sm font-medium text-white disabled:opacity-50"
            :disabled="busy"
            @click="openEditor()"
          >
            <span class="i-lucide-plus size-4" aria-hidden="true" />{{
              projectText('TEAM_ADD_MEMBER', 'Adicionar membro')
            }}
          </button>
        </header>
        <div class="overflow-x-auto">
          <table
            class="w-full min-w-[800px] text-left text-sm [&_th]:px-4 [&_th]:py-3 [&_td]:px-4 [&_td]:py-4"
          >
            <thead class="bg-n-slate-2 text-xs text-n-slate-11">
              <tr>
                <th>{{ projectText('TEAM_MEMBER', 'Membro') }}</th>
                <th>{{ projectText('TEAM_ROLE', 'Papel') }}</th>
                <th>{{ projectText('TEAM_TASKS', 'Tarefas') }}</th>
                <th>
                  {{
                    projectText(
                      'TEAM_PROJECT_ALLOCATION',
                      'Alocação no projeto'
                    )
                  }}
                </th>
                <th>
                  {{ projectText('TEAM_AVAILABILITY', 'Disponibilidade') }}
                </th>
                <th>{{ projectText('ACTIONS', 'Ações') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="member in visibleMembers"
                :key="member.id"
                class="border-t border-n-weak"
                :class="
                  selectedId === member.id
                    ? 'bg-n-blue-2'
                    : 'hover:bg-n-slate-2'
                "
              >
                <td>
                  <button
                    class="flex items-center gap-3 text-left"
                    @click="openDetails(member)"
                  >
                    <span
                      class="flex size-9 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-xs font-semibold text-n-blue-11"
                      aria-hidden="true"
                      >{{ initials(member.user?.name) }}</span
                    ><span
                      ><strong class="block text-sm">{{
                        member.user?.name
                      }}</strong
                      ><span
                        v-if="member.user?.email"
                        class="text-xs text-n-slate-11"
                        >{{ member.user.email }}</span
                      ></span
                    >
                  </button>
                </td>
                <td>
                  <span
                    class="rounded px-2 py-1 text-xs"
                    :class="
                      isOwner(member)
                        ? 'bg-n-ruby-3 text-n-ruby-11'
                        : member.role === 'manager'
                          ? 'bg-n-blue-3 text-n-blue-11'
                          : 'bg-n-slate-3 text-n-slate-11'
                    "
                    >{{ roles[member.role] || member.role }}</span
                  >
                </td>
                <td>
                  <strong>{{ memberCount(member) }}</strong>
                  <p class="mt-1 whitespace-nowrap text-xs text-n-slate-11">
                    {{ memberCount(member, 'completed') }}
                    {{ projectText('COMPLETED_LABEL', 'concluídas') }}
                  </p>
                </td>
                <td>
                  <div class="flex items-center gap-2">
                    <strong class="text-xs"
                      >{{ member.allocation_percent }}%</strong
                    ><svg
                      viewBox="0 0 100 6"
                      preserveAspectRatio="none"
                      class="h-1.5 w-20"
                      aria-hidden="true"
                    >
                      <rect
                        width="100"
                        height="6"
                        rx="3"
                        class="fill-current text-n-slate-3"
                      />
                      <rect
                        :width="member.allocation_percent"
                        height="6"
                        rx="3"
                        class="fill-current text-n-teal-9"
                      />
                    </svg>
                  </div>
                </td>
                <td>
                  <span
                    class="flex items-center gap-2 whitespace-nowrap text-xs"
                    :class="
                      member.overallocated
                        ? 'text-n-ruby-11'
                        : 'text-n-slate-11'
                    "
                    ><span
                      class="size-1.5 rounded-full bg-current"
                      aria-hidden="true"
                    />{{ availability(member) }}</span
                  ><span
                    v-if="member.total_allocation_percent != null"
                    class="mt-1 block text-xs text-n-slate-11"
                    >{{ member.total_allocation_percent }}%
                    {{ projectText('TEAM_TOTAL_ALLOCATION', 'no total') }}</span
                  >
                </td>
                <td>
                  <div class="flex gap-2">
                    <button
                      class="rounded-md border border-n-weak px-2 py-1 text-xs text-n-blue-11"
                      @click="openDetails(member)"
                    >
                      {{ projectText('DETAILS', 'Detalhes') }}</button
                    ><button
                      v-if="canManage && !isOwner(member)"
                      class="flex size-7 items-center justify-center rounded-md text-n-blue-11 hover:bg-n-blue-3 disabled:opacity-50"
                      :aria-label="
                        projectText('TEAM_EDIT_MEMBER', 'Editar participante')
                      "
                      :disabled="busy"
                      @click="openEditor(member)"
                    >
                      <span class="i-lucide-pencil size-4" aria-hidden="true" />
                    </button>
                  </div>
                </td>
              </tr>
              <tr v-if="!visibleMembers.length">
                <td colspan="6" class="py-12 text-center text-n-slate-11">
                  {{
                    projectText(
                      'TEAM_NO_RESULTS',
                      'Nenhum participante encontrado com esses filtros.'
                    )
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <footer
          class="flex flex-wrap items-center justify-between gap-3 border-t border-n-weak p-4 text-xs text-n-slate-11"
        >
          <span
            >{{ filteredMembers.length }}
            {{ projectText('TEAM_MEMBERS_COUNT', 'participantes') }}</span
          >
          <div
            v-if="filteredMembers.length > 25"
            class="flex items-center gap-3"
          >
            <button
              class="rounded-md border border-n-weak px-3 py-1.5 disabled:opacity-40"
              :disabled="page === 1"
              @click="page -= 1"
            >
              {{ projectText('PREVIOUS', 'Anterior') }}</button
            ><span
              >{{ page }} / {{ Math.ceil(filteredMembers.length / 25) }}</span
            ><button
              class="rounded-md border border-n-weak px-3 py-1.5 disabled:opacity-40"
              :disabled="page * 25 >= filteredMembers.length"
              @click="page += 1"
            >
              {{ projectText('NEXT', 'Próxima') }}
            </button>
          </div>
        </footer>
      </div>

      <aside
        v-if="selected"
        class="self-start rounded-xl border border-n-weak bg-n-solid-1 p-4"
        :aria-label="
          projectText('TEAM_MEMBER_DETAILS', 'Detalhes do participante')
        "
      >
        <div class="flex items-start gap-3">
          <span
            class="flex size-11 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-sm font-semibold text-n-blue-11"
            aria-hidden="true"
            >{{ initials(selected.user?.name) }}</span
          >
          <div class="min-w-0 flex-1">
            <h3 class="text-sm font-semibold">{{ selected.user?.name }}</h3>
            <span class="text-xs text-n-blue-11">{{
              roles[selected.role]
            }}</span>
          </div>
          <button
            class="text-n-slate-11"
            :aria-label="projectText('CLOSE_DETAILS', 'Fechar detalhes')"
            @click="selectedId = null"
          >
            <span class="i-lucide-x size-4" aria-hidden="true" />
          </button>
        </div>
        <nav
          class="mt-4 flex border-b border-n-weak"
          :aria-label="
            projectText('TEAM_DETAIL_TABS', 'Informações do participante')
          "
        >
          <button
            v-for="item in [
              ['overview', projectText('OVERVIEW', 'Visão geral')],
              ['tasks', projectText('TEAM_TASKS', 'Tarefas')],
              ['permissions', projectText('TEAM_PERMISSIONS', 'Permissões')],
            ]"
            :key="item[0]"
            class="border-b-2 px-2 py-2 text-xs"
            :class="
              panelTab === item[0]
                ? 'border-n-blue-9 text-n-blue-11'
                : 'border-transparent text-n-slate-11'
            "
            @click="panelTab = item[0]"
          >
            {{ item[1] }}
          </button>
        </nav>
        <div v-if="panelTab === 'overview'" class="mt-4 space-y-5 text-xs">
          <div>
            <div class="flex justify-between gap-2">
              <strong>{{
                projectText('TEAM_PROJECT_ALLOCATION', 'Alocação no projeto')
              }}</strong
              ><strong>{{ selected.allocation_percent }}%</strong>
            </div>
            <svg
              viewBox="0 0 100 6"
              preserveAspectRatio="none"
              class="mt-2 h-1.5 w-full"
              aria-hidden="true"
            >
              <rect
                width="100"
                height="6"
                rx="3"
                class="fill-current text-n-slate-3"
              />
              <rect
                :width="selected.allocation_percent"
                height="6"
                rx="3"
                class="fill-current text-n-blue-9"
              />
            </svg>
          </div>
          <div class="rounded-lg bg-n-blue-2 p-3 text-n-blue-11">
            <p>
              {{
                projectText(
                  'TEAM_CROSS_PROJECT_HELP',
                  'A disponibilidade considera as alocações deste participante nos projetos planejados e em execução da conta.'
                )
              }}
            </p>
            <p
              v-if="selected.total_allocation_percent != null"
              class="mt-2 font-semibold"
            >
              {{ selected.total_allocation_percent }}%
              {{ projectText('TEAM_ALLOCATED', 'alocado') }} ·
              {{ selected.available_percent }}%
              {{ projectText('TEAM_FREE', 'disponível') }}
            </p>
            <p v-else class="mt-2">
              {{
                projectText(
                  'TEAM_NO_CAPACITY',
                  'Capacidade compartilhada não informada.'
                )
              }}
            </p>
          </div>
          <dl class="space-y-3">
            <div class="flex justify-between">
              <dt>{{ projectText('TEAM_TASKS', 'Tarefas') }}</dt>
              <dd class="font-semibold">{{ memberTasks.length }}</dd>
            </div>
            <div class="flex justify-between">
              <dt>{{ projectText('TASKS_COMPLETED_SHORT', 'Concluídas') }}</dt>
              <dd class="font-semibold">{{ selectedCompleted }}</dd>
            </div>
            <div class="flex justify-between">
              <dt>
                {{
                  projectText('TEAM_TASK_HOURS', 'Horas nas tarefas atribuídas')
                }}
              </dt>
              <dd class="font-semibold">
                {{
                  (selectedWorked / 60).toLocaleString('pt-BR', {
                    maximumFractionDigits: 2,
                  })
                }}
                {{ projectText('HOURS_UNIT', 'h') }}
              </dd>
            </div>
          </dl>
          <p class="text-n-slate-11">
            {{
              projectText(
                'TEAM_HOURS_HINT',
                'As horas pertencem às tarefas atualmente atribuídas e podem incluir apontamentos de outros participantes.'
              )
            }}
          </p>
        </div>
        <div
          v-if="panelTab === 'tasks'"
          class="mt-3 max-h-[480px] overflow-y-auto"
        >
          <RouterLink
            v-for="task in memberTasks"
            :key="task.id"
            :to="taskRoute(task)"
            class="block border-b border-n-weak py-3 hover:text-n-blue-11"
          >
            <strong class="block text-xs">{{ task.title }}</strong
            ><span class="mt-1 block text-xs text-n-slate-11"
              >{{ projectTaskStatuses[task.status] || task.status }} ·
              {{ formatDate(task.due_on) }}</span
            >
          </RouterLink>
          <p
            v-if="!memberTasks.length"
            class="py-6 text-center text-xs text-n-slate-11"
          >
            {{ projectText('TEAM_NO_TASKS', 'Nenhuma tarefa atribuída.') }}
          </p>
        </div>
        <div v-if="panelTab === 'permissions'" class="mt-4 space-y-3 text-xs">
          <strong>{{ roles[selected.role] }}</strong>
          <p class="text-n-slate-11">{{ roleDescriptions[selected.role] }}</p>
          <p class="text-n-slate-11">
            {{
              projectText(
                'TEAM_PERMISSION_HELP',
                'As permissões do perfil na conta também se aplicam ao acesso ao projeto.'
              )
            }}
          </p>
        </div>
        <div
          v-if="canManage && !isOwner(selected)"
          class="mt-5 flex gap-2 border-t border-n-weak pt-4"
        >
          <button
            class="flex-1 rounded-md border border-n-weak px-3 py-2 text-xs text-n-blue-11 disabled:opacity-50"
            :disabled="busy"
            @click="openEditor(selected)"
          >
            {{ projectText('TEAM_EDIT_MEMBER', 'Editar participante') }}</button
          ><button
            class="rounded-md border border-n-weak px-3 py-2 text-xs text-n-ruby-11 disabled:opacity-50"
            :disabled="busy"
            @click="remove(selected)"
          >
            {{ projectText('TEAM_REMOVE', 'Remover') }}
          </button>
        </div>
        <p
          v-else-if="isOwner(selected)"
          class="mt-4 border-t border-n-weak pt-3 text-xs text-n-slate-11"
        >
          {{
            projectText(
              'TEAM_OWNER_TRANSFER_HELP',
              'A troca do proprietário é feita nos dados gerais do projeto.'
            )
          }}
        </p>
      </aside>
    </div>

    <OpsModal
      v-if="modal"
      :title="
        editing
          ? projectText('TEAM_EDIT_MEMBER', 'Editar participante')
          : projectText('TEAM_ADD_MEMBER', 'Adicionar membro')
      "
      :busy="busy"
      @close="modal = false"
    >
      <form class="space-y-4" @submit.prevent="save">
        <p
          v-if="error"
          role="alert"
          class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm"
        >
          {{ error }}
        </p>
        <p v-if="loadingOptions" role="status" class="text-sm text-n-slate-11">
          {{ projectText('TEAM_LOADING_USERS', 'Carregando usuários...') }}
        </p>
        <fieldset
          :disabled="busy || loadingOptions"
          class="grid gap-4 md:grid-cols-2"
        >
          <label class="flex flex-col gap-2 md:col-span-2"
            ><span class="text-sm font-medium">{{
              projectText('TEAM_MEMBER', 'Membro')
            }}</span
            ><input
              v-if="editing"
              :value="editing.user?.name"
              disabled
              class="rounded-lg border border-n-weak bg-n-slate-2 p-2"
            /><select
              v-else
              v-model="form.user_id"
              required
              class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option value="">
                {{ projectText('TEAM_SELECT_USER', 'Selecione um usuário') }}
              </option>
              <option
                v-for="user in availableUsers"
                :key="user.id"
                :value="user.id"
              >
                {{ user.name }}
              </option>
            </select></label
          >
          <label class="flex flex-col gap-2"
            ><span class="text-sm font-medium">{{
              projectText('TEAM_ROLE', 'Papel')
            }}</span
            ><select
              v-model="form.role"
              required
              class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
            >
              <option
                v-for="[key, label] in editableRoles"
                :key="key"
                :value="key"
              >
                {{ label }}
              </option>
            </select></label
          >
          <label class="flex flex-col gap-2"
            ><span class="text-sm font-medium">{{
              projectText('TEAM_ALLOCATION_PERCENT', 'Alocação prevista (%)')
            }}</span
            ><input
              v-model.number="form.allocation_percent"
              type="number"
              min="0"
              max="100"
              step="1"
              required
              class="rounded-lg border border-n-weak bg-n-solid-1 p-2"
          /></label>
        </fieldset>
        <p class="text-xs text-n-slate-11">{{ roleDescriptions[form.role] }}</p>
        <footer class="flex justify-end gap-3 border-t border-n-weak pt-4">
          <button
            type="button"
            class="rounded-lg border border-n-weak px-4 py-2 text-sm"
            :disabled="busy"
            @click="modal = false"
          >
            {{ projectText('CANCEL', 'Cancelar') }}</button
          ><button
            type="submit"
            class="rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-medium text-white disabled:opacity-50"
            :disabled="busy || loadingOptions || !form.user_id"
          >
            {{
              busy
                ? projectText('SAVING', 'Salvando...')
                : projectText('SAVE', 'Salvar')
            }}
          </button>
        </footer>
      </form>
    </OpsModal>
  </section>
</template>
