<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { routeTo } from '../jrcOperations/api';
import { useProjects } from './useProjects';
const route = useRoute();
const { accountId, status, enabled, loading, error, refresh, projectText } =
  useProjects();
const settingsRoute = computed(() => route.name === 'jrc_projects_settings');
const canRender = computed(() => enabled.value || settingsRoute.value);
</script>

<template>
  <main
    class="flex min-w-0 flex-1 flex-col overflow-auto bg-n-background text-n-slate-12 [&_button:focus-visible]:outline [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-offset-2 [&_button:focus-visible]:outline-n-blue-9 [&_button:disabled]:cursor-not-allowed [&_button:disabled]:opacity-50 [&_h1]:font-semibold [&_h2]:font-semibold [&_h3]:font-semibold"
  >
    <div class="mx-auto w-full min-w-0 max-w-[1920px] p-4 lg:p-5">
      <RouterLink
        v-if="settingsRoute"
        class="mb-4 inline-flex items-center gap-2 text-sm text-n-blue-11"
        :to="routeTo('jrc_projects_list', accountId)"
      >
        <span class="i-lucide-chevron-left size-4" />{{
          projectText('PROJECTS', 'Projetos')
        }}
      </RouterLink>
      <p
        v-if="loading && !status"
        class="p-6 text-sm text-n-slate-11"
        role="status"
      >
        {{
          projectText(
            'LOADING_PROJECT_ACCESS',
            'Carregando acesso aos projetos...'
          )
        }}
      </p>
      <div
        v-else-if="error"
        class="rounded-xl border border-n-ruby-7 bg-n-ruby-2 p-4"
        role="alert"
      >
        {{ error
        }}<button class="ml-3 text-n-blue-11 underline" @click="refresh(true)">
          {{ projectText('RETRY', 'Tentar novamente') }}
        </button>
      </div>
      <section
        v-else-if="!canRender"
        class="rounded-xl border border-n-weak bg-n-solid-1 p-6"
      >
        <h2>
          {{ projectText('PROJECTS_DISABLED', 'Projetos ainda não ativado') }}
        </h2>
        <p class="mt-2 text-sm text-n-slate-11">
          {{
            projectText(
              'PROJECTS_ACCESS_HELP',
              'O Super Admin deve habilitar Projetos para esta conta, e o administrador deve conceder seu acesso.'
            )
          }}
        </p>
        <RouterLink
          v-if="status?.administrator"
          class="mt-4 inline-block rounded-lg bg-n-blue-9 px-4 py-2 text-sm text-white"
          :to="routeTo('jrc_projects_settings', accountId)"
        >
          {{
            projectText(
              'OPEN_PROJECT_SETTINGS',
              'Abrir configurações de Projetos'
            )
          }}
        </RouterLink>
      </section>
      <RouterView v-else />
    </div>
  </main>
</template>
