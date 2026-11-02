<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useRouter } from 'vue-router';
import { useProjects } from '../../jrcProjects/useProjects';
import {
  statusTone,
  priorityTone,
  initials,
  isOverdue,
  useProjectPreferences,
} from '../../jrcProjects/projectPresentation';
import ProjectPortfolioSummary from '../../jrcProjects/components/ProjectPortfolioSummary.vue';
import {
  request,
  allPages,
  errorMessage,
  projectStatuses,
  routeTo,
  formatDate,
  priorities,
  dateInput,
} from '../api';
import CreateProject from '../components/CreateProject.vue';
import DeleteProjectButton from '../../jrcProjects/components/DeleteProjectButton.vue';

const { accountId, userId, status, canCreate, projectText } = useProjects();
const router = useRouter();
const preferenceKey = computed(
  () => 'jrc:projects:portfolio:' + accountId.value + ':' + userId.value
);
const filters = useProjectPreferences(preferenceKey, {
  q: '',
  status: '',
  priority: '',
  owner: '',
  contact: '',
  view: 'overview',
});
const rows = ref([]);
const portfolio = ref(null);
const meta = ref({ total: 0 });
const page = ref(1);
const pageSize = 12;
const error = ref('');
const summaryError = ref('');
const loading = ref(false);
const exporting = ref(false);
const creating = ref(false);
const today = dateInput();
const canExport = computed(() =>
  rows.value.some(project =>
    project.capabilities?.includes('projects.report.export')
  )
);
let generation = 0;
let summaryGeneration = 0;
let debounce;
const queryParams = () => ({
  q: filters.q,
  status: filters.status === 'overdue' ? '' : filters.status,
  overdue: filters.status === 'overdue' ? 'true' : undefined,
  priority: filters.priority,
  owner_id: filters.owner,
  contact_id: filters.contact,
});
async function load() {
  generation += 1;
  const current = generation;
  if (!status.value?.projects_enabled) return;
  loading.value = true;
  error.value = '';
  try {
    const result = await request(accountId.value, 'projects/projects', {
      params: { ...queryParams(), page: page.value, per_page: pageSize },
    });
    if (current !== generation) return;
    rows.value = result.data;
    meta.value = result.meta;
  } catch (err) {
    if (current === generation) error.value = errorMessage(err);
  } finally {
    if (current === generation) loading.value = false;
  }
}
async function loadSummary() {
  summaryGeneration += 1;
  const current = summaryGeneration;
  portfolio.value = null;
  summaryError.value = '';
  if (!status.value?.projects_enabled) return;
  try {
    const result = await request(accountId.value, 'projects/portfolio');
    if (current === summaryGeneration) portfolio.value = result.data;
  } catch (err) {
    if (current === summaryGeneration) summaryError.value = errorMessage(err);
  }
}
watch(
  () => [accountId.value, userId.value, status.value?.projects_enabled],
  () => {
    clearTimeout(debounce);
    generation += 1;
    page.value = 1;
    rows.value = [];
    meta.value = { total: 0 };
    load();
    loadSummary();
  },
  { immediate: true }
);
watch(
  () => [
    filters.q,
    filters.status,
    filters.priority,
    filters.owner,
    filters.contact,
  ],
  () => {
    generation += 1;
    page.value = 1;
    clearTimeout(debounce);
    debounce = setTimeout(load, 250);
  }
);
onBeforeUnmount(() => {
  clearTimeout(debounce);
  generation += 1;
  summaryGeneration += 1;
});
function search() {
  clearTimeout(debounce);
  page.value = 1;
  load();
}
function clearFilters() {
  Object.assign(filters, {
    q: '',
    status: '',
    priority: '',
    owner: '',
    contact: '',
  });
}
function navigatePage(delta) {
  page.value += delta;
  load();
}
function created(project) {
  creating.value = false;
  router.push(
    routeTo('jrc_projects_detail', accountId.value, { projectId: project.id })
  );
}
async function deleted() {
  if (rows.value.length === 1 && page.value > 1) page.value -= 1;
  await Promise.all([load(), loadSummary()]);
}
async function exportProjects() {
  if (exporting.value) return;
  exporting.value = true;
  error.value = '';
  try {
    const projects = (
      await allPages(accountId.value, 'projects/projects', queryParams())
    ).filter(project =>
      project.capabilities?.includes('projects.report.export')
    );
    const cell = value =>
      '"' +
      String(value ?? '')
        .replace(/^(?:\s*[=+@-]|[\t\r])/, "'$&")
        .replaceAll('"', '""') +
      '"';
    const data = [
      [
        'Código',
        'Projeto',
        'Situação',
        'Prioridade',
        'Cliente',
        'Responsável',
        'Entrega',
        'Tarefas concluídas',
        'Tarefas',
        'Progresso (%)',
      ],
      ...projects.map(project => [
        project.key,
        project.name,
        projectStatuses[project.status],
        priorities[project.priority],
        project.contact?.name,
        project.owner?.name,
        project.due_on,
        project.tasks_completed,
        project.tasks_total,
        project.progress,
      ]),
    ];
    const url = URL.createObjectURL(
      new Blob(
        ['\uFEFF' + data.map(row => row.map(cell).join(';')).join('\r\n')],
        { type: 'text/csv;charset=utf-8;' }
      )
    );
    const link = document.createElement('a');
    link.href = url;
    link.download = 'projetos-' + today + '.csv';
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  } catch (err) {
    error.value = errorMessage(err);
  } finally {
    exporting.value = false;
  }
}
</script>

<template>
  <section class="flex min-w-0 flex-col gap-4">
    <header class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <p class="mb-1 text-xs text-n-blue-11">
          {{ projectText('PROJECTS_BREADCRUMB', 'JRC Conversas / Projetos') }}
        </p>
        <h1 class="text-2xl font-semibold">
          {{ projectText('PROJECTS', 'Projetos') }}
        </h1>
        <p class="mt-1 text-sm text-n-slate-11">
          {{
            projectText(
              'PROJECTS_DESCRIPTION',
              'Gestão de projetos, tarefas, planejamento e entregas.'
            )
          }}
        </p>
      </div>
      <div class="flex flex-wrap items-center gap-2">
        <button
          v-if="canExport"
          class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :disabled="exporting"
          @click="exportProjects"
        >
          <span class="i-lucide-download size-4" />{{
            projectText('EXPORT_PROJECTS', 'Exportar')
          }}
        </button>
        <RouterLink
          v-if="status?.administrator"
          class="flex items-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm"
          :to="routeTo('jrc_projects_settings', accountId)"
        >
          <span class="i-lucide-settings size-4" />{{
            projectText('CONFIGURATION', 'Configurações')
          }}
        </RouterLink>
        <button
          v-if="canCreate"
          class="flex items-center gap-2 rounded-lg bg-n-blue-9 px-4 py-2 text-sm font-medium text-white hover:bg-n-blue-10"
          @click="creating = true"
        >
          <span class="i-lucide-plus size-4" />{{
            projectText('NEW_PROJECT', 'Novo projeto')
          }}
        </button>
      </div>
    </header>
    <nav
      class="flex gap-5 border-b border-n-weak"
      :aria-label="projectText('PORTFOLIO_NAVIGATION', 'Navegação de projetos')"
    >
      <button
        v-for="item in [
          ['overview', projectText('OVERVIEW', 'Visão geral')],
          ['projects', projectText('PROJECTS', 'Projetos')],
        ]"
        :key="item[0]"
        class="border-b-2 px-2 py-3 text-sm font-medium"
        :class="
          filters.view === item[0]
            ? 'border-n-blue-9 text-n-blue-11'
            : 'border-transparent text-n-slate-11'
        "
        :aria-current="filters.view === item[0] ? 'page' : undefined"
        @click="filters.view = item[0]"
      >
        {{ item[1] }}
      </button>
    </nav>
    <template v-if="filters.view === 'overview'">
      <ProjectPortfolioSummary
        v-if="portfolio"
        :portfolio="portfolio"
        @filter="filters.status = $event"
      />
      <div
        v-else-if="summaryError"
        class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-4 text-sm"
        role="alert"
      >
        {{ summaryError
        }}<button class="ml-3 text-n-blue-11 underline" @click="loadSummary">
          {{ projectText('RETRY', 'Tentar novamente') }}
        </button>
      </div>
      <div
        v-else
        class="grid grid-cols-2 gap-3 lg:grid-cols-5"
        role="status"
        :aria-label="projectText('LOADING_SUMMARY', 'Carregando indicadores')"
      >
        <div
          v-for="index in 5"
          :key="index"
          class="h-28 animate-pulse rounded-xl bg-n-slate-3"
        />
      </div>
    </template>
    <form
      class="grid grid-cols-2 items-center gap-2 lg:grid-cols-[minmax(200px,2fr)_repeat(4,minmax(120px,1fr))_auto]"
      @submit.prevent="search"
    >
      <label class="relative col-span-2 lg:col-span-1"
        ><span
          class="i-lucide-search pointer-events-none absolute left-3 top-3 size-4 text-n-slate-10" /><input
          v-model="filters.q"
          class="w-full rounded-lg border border-n-weak bg-n-solid-1 py-2.5 pl-9 pr-3 text-xs"
          :placeholder="
            projectText(
              'SEARCH_PROJECTS',
              'Pesquisar por nome, código, cliente ou responsável...'
            )
          "
          :aria-label="projectText('SEARCH_PROJECTS', 'Pesquisar projetos')"
      /></label>
      <select
        v-model="filters.status"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-xs"
        :aria-label="projectText('PROJECT_STATUS', 'Situação do projeto')"
      >
        <option value="">
          {{ projectText('ALL_STATUSES', 'Todas as situações') }}
        </option>
        <option
          v-for="(label, value) in projectStatuses"
          :key="value"
          :value="value"
        >
          {{ label }}
        </option>
        <option value="overdue">
          {{ projectText('PORTFOLIO_OVERDUE', 'Em atraso') }}
        </option>
      </select>
      <select
        v-model="filters.priority"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-xs"
        :aria-label="projectText('PRIORITY', 'Prioridade')"
      >
        <option value="">
          {{ projectText('ALL_PRIORITIES', 'Todas as prioridades') }}
        </option>
        <option
          v-for="(label, value) in priorities"
          :key="value"
          :value="value"
        >
          {{ label }}
        </option>
      </select>
      <select
        v-model="filters.contact"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-xs"
        :aria-label="projectText('CUSTOMER', 'Cliente')"
      >
        <option value="">
          {{ projectText('ALL_CUSTOMERS', 'Todos os clientes') }}
        </option>
        <option
          v-for="contact in portfolio?.filter_options?.contacts || []"
          :key="contact.id"
          :value="String(contact.id)"
        >
          {{ contact.name }}
        </option>
      </select>
      <select
        v-model="filters.owner"
        class="w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-xs"
        :aria-label="projectText('OWNER', 'Responsável')"
      >
        <option value="">
          {{ projectText('ALL_OWNERS', 'Todos os responsáveis') }}
        </option>
        <option
          v-for="owner in portfolio?.filter_options?.owners || []"
          :key="owner.id"
          :value="String(owner.id)"
        >
          {{ owner.name }}
        </option>
      </select>
      <button
        type="button"
        class="flex items-center justify-center gap-2 whitespace-nowrap rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-xs"
        @click="clearFilters"
      >
        <span class="i-lucide-filter-x size-4" />{{
          projectText('CLEAR_FILTERS', 'Limpar filtros')
        }}
      </button>
    </form>
    <div
      v-if="error"
      class="rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-4 text-sm"
      role="alert"
    >
      {{ error
      }}<button class="ml-3 text-n-blue-11 underline" @click="load">
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <p
      v-if="loading"
      class="py-6 text-center text-sm text-n-slate-11"
      role="status"
    >
      {{ projectText('LOADING_PROJECTS', 'Carregando projetos...') }}
    </p>
    <div
      v-else-if="!error && !rows.length"
      class="rounded-xl border border-dashed border-n-weak bg-n-solid-1 px-6 py-12 text-center"
    >
      <span
        class="i-lucide-folder-open mx-auto mb-3 block size-10 text-n-slate-9"
      />
      <h3>
        {{ projectText('NO_PROJECTS_FOUND', 'Nenhum projeto encontrado') }}
      </h3>
      <p class="mt-2 text-sm text-n-slate-11">
        {{
          projectText(
            'NO_PROJECTS_HELP',
            'Ajuste os filtros ou crie um projeto para organizar sua próxima entrega.'
          )
        }}
      </p>
    </div>
    <div
      v-else-if="!error"
      class="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3"
    >
      <article
        v-for="project in rows"
        :key="project.id"
        class="flex min-w-0 flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 shadow-sm transition hover:border-n-blue-7"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <span class="text-xs font-medium text-n-blue-11">{{
            project.key
          }}</span>
          <div class="flex gap-1.5">
            <span
              class="rounded-md px-2 py-0.5 text-xs font-medium"
              :class="statusTone(project.status)"
              >{{ projectStatuses[project.status] }}</span
            ><span
              class="rounded-md px-2 py-0.5 text-xs font-medium"
              :class="priorityTone(project.priority)"
              >{{ priorities[project.priority] }}</span
            >
          </div>
        </div>
        <div>
          <RouterLink
            class="block truncate text-base font-semibold text-n-slate-12 hover:text-n-blue-11"
            :to="
              routeTo('jrc_projects_detail', accountId, {
                projectId: project.id,
              })
            "
          >
            {{ project.name }}
          </RouterLink>
          <p class="mt-1 truncate text-xs text-n-slate-11">
            {{
              project.contact?.name ||
              projectText('INTERNAL_PROJECT', 'Projeto interno')
            }}
            · {{ project.owner?.name }}
          </p>
        </div>
        <div>
          <div class="mb-1.5 flex justify-between text-xs">
            <span
              >{{ project.tasks_completed }}/{{ project.tasks_total }}
              {{ projectText('TASKS', 'tarefas') }}</span
            ><strong>{{ project.progress }}%</strong>
          </div>
          <progress
            :value="project.progress"
            max="100"
            class="block h-1.5 w-full overflow-hidden rounded-full accent-blue-600 [&::-webkit-progress-bar]:rounded-full [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9"
            :aria-label="
              projectText('PROGRESS', 'Progresso') + ': ' + project.name
            "
          />
        </div>
        <div
          class="flex flex-wrap items-center gap-3 border-t border-n-weak pt-2 text-xs text-n-slate-11"
        >
          <span
            class="flex items-center gap-1"
            :class="{ 'text-n-ruby-11': isOverdue(project, today) }"
            ><span class="i-lucide-calendar-days size-3.5" />{{
              formatDate(project.due_on)
            }}</span
          ><span
            v-if="project.members_count != null"
            class="flex items-center gap-1"
            ><span class="i-lucide-users size-3.5" />{{
              project.members_count
            }}</span
          ><span
            v-if="project.comments_count != null"
            class="flex items-center gap-1"
            :title="projectText('COMMENTS', 'Comentários')"
            ><span class="i-lucide-message-circle size-3.5" />{{
              project.comments_count
            }}</span
          ><span
            v-if="project.attachments_count != null"
            class="flex items-center gap-1"
            :title="projectText('FILES', 'Arquivos')"
            ><span class="i-lucide-paperclip size-3.5" />{{
              project.attachments_count
            }}</span
          ><span
            v-if="isOverdue(project, today)"
            class="font-medium text-n-ruby-11"
            >{{ projectText('OVERDUE', 'Atrasado') }}</span
          >
        </div>
        <div class="mt-auto flex items-center justify-between">
          <span
            class="flex size-7 items-center justify-center rounded-full bg-n-blue-3 text-[10px] font-semibold text-n-blue-11"
            :title="project.owner?.name"
            >{{ initials(project.owner?.name) }}</span
          >
          <div class="ml-auto flex items-center gap-2">
            <RouterLink
              v-if="project.capabilities?.includes('projects.project.update')"
              class="rounded-lg border border-n-weak p-2 text-n-blue-11 hover:bg-n-blue-2"
              :to="{
                ...routeTo('jrc_projects_detail', accountId, {
                  projectId: project.id,
                }),
                query: { tab: 'settings' },
              }"
              :aria-label="projectText('EDIT_PROJECT', 'Editar projeto')"
              :title="projectText('EDIT_PROJECT', 'Editar projeto')"
              ><span
                class="i-lucide-pencil block size-3.5 shrink-0"
                aria-hidden="true"
            /></RouterLink>
            <DeleteProjectButton
              :project="project"
              compact
              :disabled="loading"
              @deleted="deleted"
              @error="error = $event"
            />
            <RouterLink
              class="rounded-lg border border-n-blue-5 bg-n-blue-2 px-3 py-1.5 text-xs font-semibold text-n-blue-11 hover:bg-n-blue-3"
              :to="
                routeTo('jrc_projects_detail', accountId, {
                  projectId: project.id,
                })
              "
            >
              {{ projectText('OPEN_PROJECT', 'Abrir projeto') }}
            </RouterLink>
          </div>
        </div>
      </article>
    </div>
    <footer
      class="flex flex-wrap items-center justify-between gap-3 py-2 text-sm text-n-slate-11"
    >
      <span
        >{{ meta.total }}
        {{ projectText('PROJECTS_IN_FILTER', 'projetos neste filtro') }}</span
      >
      <div v-if="meta.total > pageSize" class="flex items-center gap-3">
        <button
          class="rounded-lg border border-n-weak px-3 py-1.5 disabled:opacity-40"
          :disabled="page === 1 || loading"
          @click="navigatePage(-1)"
        >
          {{ projectText('PREVIOUS', 'Anterior') }}</button
        ><span>{{ page }}/{{ Math.ceil(meta.total / pageSize) }}</span
        ><button
          class="rounded-lg border border-n-weak px-3 py-1.5 disabled:opacity-40"
          :disabled="page * pageSize >= meta.total || loading"
          @click="navigatePage(1)"
        >
          {{ projectText('NEXT', 'Próxima') }}
        </button>
      </div>
    </footer>
    <CreateProject
      v-if="creating"
      @close="creating = false"
      @created="created"
    />
  </section>
</template>
