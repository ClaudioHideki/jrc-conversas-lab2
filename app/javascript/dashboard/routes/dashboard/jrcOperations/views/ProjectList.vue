<script setup>
import { ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import { useProjects } from '../../jrcProjects/useProjects';
import {
  request,
  errorMessage,
  projectStatuses,
  routeTo,
  formatDate,
  priorities,
} from '../api';
import CreateProject from '../components/CreateProject.vue';
const { accountId, status, projectText } = useProjects();
const router = useRouter();
const rows = ref([]);
const meta = ref({ total: 0 });
const page = ref(1);
const q = ref('');
const filter = ref('');
const priority = ref('');
const error = ref('');
const loading = ref(false);
const creating = ref(false);
let generation = 0;
async function load() {
  const current = ++generation;
  if (!status.value?.projects_enabled) {
    rows.value = [];
    meta.value = { total: 0 };
    loading.value = false;
    return;
  }
  loading.value = true;
  error.value = '';
  try {
    const result = await request(accountId.value, 'projects/projects', {
      params: {
        page: page.value,
        q: q.value,
        status: filter.value,
        priority: priority.value,
        per_page: 25,
      },
    });
    if (current === generation) {
      rows.value = result.data;
      meta.value = result.meta;
    }
  } catch (err) {
    if (current === generation) error.value = errorMessage(err);
  } finally {
    if (current === generation) loading.value = false;
  }
}
watch(
  () => [accountId.value, status.value?.projects_enabled],
  () => {
    page.value = 1;
    rows.value = [];
    meta.value = { total: 0 };
    load();
  },
  { immediate: true }
);
function search() {
  page.value = 1;
  load();
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
</script>

<template>
  <section class="flex flex-col gap-4">
    <header class="flex flex-wrap items-center gap-3 justify-between">
      <div>
        <h2>Projetos e entregas</h2>
        <p class="text-n-slate-11 text-sm">
          Do compromisso comercial ao aceite, com contexto de atendimento.
        </p>
      </div>
      <button
        v-if="status?.can_create_project"
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed bg-n-blue-9 text-white"
        @click="creating = true"
      >
        Novo projeto
      </button>
    </header>
    <div
      v-if="error"
      class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
      role="alert"
    >
      {{ error }}
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
        :disabled="loading"
        @click="load"
      >
        {{ projectText('RETRY', 'Tentar novamente') }}
      </button>
    </div>
    <form class="flex flex-wrap items-center gap-3" @submit.prevent="search">
      <input
        v-model="q"
        class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[340px]"
        placeholder="Pesquisar projeto"
        aria-label="Pesquisar projeto"
      /><select
        v-model="filter"
        class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[200px]"
        aria-label="Situacao"
      >
        <option value="">Todas as situacoes</option>
        <option
          v-for="(label, value) in projectStatuses"
          :key="value"
          :value="value"
        >
          {{ label }}
        </option></select><select
        v-model="priority"
        class="rounded border border-n-weak bg-n-solid-1 p-2 max-w-[200px]"
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
        </option></select><button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
        :disabled="loading"
      >
        Pesquisar</button><span class="text-n-slate-11 text-sm">{{ meta.total }} projetos no seu acesso</span>
    </form>
    <div v-if="loading" class="p-4 text-n-slate-11" role="status">
      Carregando projetos...
    </div>
    <div
      v-else-if="!error && !rows.length"
      class="rounded-xl border border-n-weak bg-n-solid-1 p-4 p-6 text-center text-n-slate-11"
    >
      Nenhum projeto neste filtro. Os projetos sao compartilhados pela
      participacao na equipe ou pela visibilidade definida.
    </div>
    <div v-else-if="!error" class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <article
        v-for="project in rows"
        :key="project.id"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
      >
        <div class="flex flex-wrap items-center gap-3 justify-between">
          <span class="text-sm text-n-blue-11">{{ project.key }}</span><span class="rounded px-2 py-1 text-xs border border-n-weak">{{
            projectStatuses[project.status] || project.status
          }}</span>
        </div>
        <RouterLink
          class="text-n-blue-11 underline"
          :to="
            routeTo('jrc_projects_detail', accountId, { projectId: project.id })
          "
        >
          <h2>{{ project.name }}</h2>
        </RouterLink>
        <p class="rounded px-2 py-1 text-xs border border-n-weak">
          {{ projectText('PRIORITY', 'Prioridade') }}:
          {{ priorities[project.priority] }}
        </p>
        <p class="text-n-slate-11 text-sm">
          {{ project.contact?.name || 'Projeto interno' }} · Responsavel:
          {{ project.owner?.name }}
        </p>
        <div>
          <div class="flex flex-wrap items-center gap-3 justify-between">
            <span class="text-n-slate-11 text-sm">{{ project.tasks_completed }}/{{ project.tasks_total }} tarefas
              concluidas</span><strong>{{ project.progress }}%</strong>
          </div>
          <progress
            :value="project.progress"
            max="100"
            class="w-full h-2"
            :aria-label="`Progresso de ${project.name}`"
          />
        </div>
        <div class="flex flex-wrap items-center gap-3 justify-between">
          <span class="text-n-slate-11 text-sm">Entrega: {{ formatDate(project.due_on) }}</span><RouterLink
            class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
            :to="
              routeTo('jrc_projects_detail', accountId, {
                projectId: project.id,
              })
            "
          >
            Abrir projeto
          </RouterLink>
        </div>
      </article>
    </div>
    <footer
      v-if="meta.total > 25"
      class="flex justify-end items-center gap-3 pt-4"
    >
      <button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
        :disabled="page === 1 || loading"
        @click="navigatePage(-1)"
      >
        Anterior</button><span>Pagina {{ page }}</span><button
        class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed"
        :disabled="page * 25 >= meta.total || loading"
        @click="navigatePage(1)"
      >
        Proxima
      </button>
    </footer>
    <CreateProject
      v-if="creating"
      @close="creating = false"
      @created="created"
    />
  </section>
</template>
