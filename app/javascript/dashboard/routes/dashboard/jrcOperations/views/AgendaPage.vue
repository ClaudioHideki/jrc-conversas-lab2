<script setup>
import { routeTo } from '../api';
import { useAgenda } from '../useAgenda';
import OperationsAgenda from './OperationsAgenda.vue';
const { accountId, agendaText } = useAgenda();
</script>

<template>
  <main
    class="text-n-slate-12 [&_button:focus-visible]:outline [&_button:focus-visible]:outline-2 [&_button:focus-visible]:outline-n-blue-9 [&_h1]:text-2xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold flex flex-col flex-1 min-w-0 overflow-auto text-n-slate-12 bg-n-background"
  >
    <header class="p-5 border-b border-n-weak">
      <p class="text-sm text-n-blue-11">
        {{ agendaText('AGENDA_EYEBROW', 'JRC Conversas / Agenda') }}
      </p>
      <div class="flex flex-wrap items-center gap-3 justify-between">
        <div>
          <h1>{{ agendaText('MY_AGENDA', 'Minha Agenda') }}</h1>
          <p class="text-n-slate-11 text-sm">
            {{
              agendaText(
                'AGENDA_DESCRIPTION',
                'Compromissos de CRM e Projetos sem duplicar os registros de origem.'
              )
            }}
          </p>
        </div>
        <RouterLink
          class="rounded-md border border-n-weak px-3 py-2 text-sm disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:opacity-100 disabled:cursor-not-allowed text-xs"
          :to="routeTo('jrc_cockpit', accountId)"
        >
          {{ agendaText('BACK_COCKPIT', 'Voltar ao Cockpit') }}
        </RouterLink>
      </div>
    </header>
    <div class="p-5"><OperationsAgenda /></div>
  </main>
</template>
