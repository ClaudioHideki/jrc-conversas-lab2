<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { routeTo } from '../jrcOperations/api';
import { useProjects } from './useProjects';

const route = useRoute();
const { accountId, status, enabled, loading, error, refresh } = useProjects();
const settingsRoute = computed(() => route.name === 'jrc_projects_settings');
const canRender = computed(() => enabled.value || settingsRoute.value);
</script>

<template>
  <main
    class="text-n-slate-12 [&_button:focus-visible]:outline [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-n-blue-9 [&_h1]:text-2xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold flex flex-col flex-1 min-w-0 overflow-auto text-n-slate-12 bg-n-background"
  >
    <header class="p-5 border-b border-n-weak">
      <p class="text-sm text-n-blue-11">JRC Conversas / Projetos</p>
      <div class="flex flex-wrap items-center gap-3 justify-between">
        <div>
          <h1>Projetos</h1>
          <p class="text-n-slate-11 text-sm">
            Gestao de projetos, tarefas, planejamento e entregas.
          </p>
        </div>
        <RouterLink
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          :to="routeTo('jrc_cockpit', accountId)"
        >
          Voltar ao Cockpit
        </RouterLink>
      </div>
      <nav
        class="flex gap-3 overflow-x-auto py-3 [&_button]:rounded-lg [&_button]:px-3 [&_button]:py-2 [&_a]:px-3 [&_a]:py-2 [&_.active]:bg-n-blue-9 [&_.active]:text-white [&_.router-link-exact-active]:text-n-blue-11"
        aria-label="Projetos"
      >
        <RouterLink
          v-if="enabled"
          :to="routeTo('jrc_projects_list', accountId)"
        >
          Projetos
        </RouterLink>
        <RouterLink
          v-if="status?.administrator"
          :to="routeTo('jrc_projects_settings', accountId)"
        >
          Configuracoes
        </RouterLink>
      </nav>
    </header>
    <div class="p-5">
      <div v-if="loading && !status" class="p-4 text-n-slate-11" role="status">
        Carregando permissoes da conta...
      </div>
      <div
        v-else-if="error"
        class="rounded border border-n-ruby-7 bg-n-ruby-2 p-3"
        role="alert"
      >
        {{ error }}
        <button
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          @click="refresh(true)"
        >
          Tentar novamente
        </button>
      </div>
      <section
        v-else-if="!canRender"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-4 flex flex-col gap-4"
      >
        <h2>Projetos ainda nao ativado</h2>
        <p>
          O Super Admin deve habilitar Projetos para esta conta, e o
          administrador deve conceder seu acesso.
        </p>
        <RouterLink
          v-if="status?.administrator"
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed bg-n-blue-9 text-white"
          :to="routeTo('jrc_projects_settings', accountId)"
        >
          Abrir configuracoes de Projetos
        </RouterLink>
      </section>
      <RouterView v-else />
    </div>
  </main>
</template>
