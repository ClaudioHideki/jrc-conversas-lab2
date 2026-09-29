<script setup>
import { crmControlClasses } from '../../crmControlClasses';
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import CrmStatusBadge from '../../components/shared/CrmStatusBadge.vue';
import { formatCrmDateTime } from '../../utils/dateTime';

defineProps({
  lead: { type: Object, required: true },
  saving: { type: Boolean, default: false },
});
const emit = defineEmits([
  'close',
  'status-change',
  'convert',
  'conversation',
  'contact',
  'deal',
]);
const historyText = event =>
  event.event_type === 'lead_converted'
    ? 'Lead convertido em negócio'
    : `Status alterado de ${event.from_value || '—'} para ${event.to_value || '—'}`;
</script>

<template>
  <div
    :class="crmControlClasses" class="fixed inset-0 z-[85] flex justify-end bg-black/55"
    @click.self="emit('close')"
  >
    <aside
      class="flex h-full w-full max-w-xl flex-col border-l border-n-weak bg-n-solid-2 shadow-2xl"
    >
      <header
        class="flex items-start justify-between border-b border-n-weak bg-n-alpha-2 p-6"
      >
        <div>
          <p class="text-xs font-semibold uppercase tracking-wide text-n-brand">
            Lead #{{ lead.id }}
          </p>
          <h3 class="mt-1 text-2xl font-bold text-n-slate-12">
            {{ lead.name }}
          </h3>
          <p class="mt-1 text-sm text-n-slate-11">
            {{ lead.company_name || 'Empresa não informada' }}
          </p>
        </div>
        <button
          type="button"
          class="rounded-lg p-2 text-n-slate-11 hover:bg-n-alpha-3"
          aria-label="Fechar"
          @click="emit('close')"
        >
          <i class="i-lucide-x size-5" />
        </button>
      </header>
      <div class="flex-1 overflow-y-auto p-6">
        <section
          class="grid grid-cols-2 gap-4 rounded-2xl border border-n-weak bg-n-solid-1 p-4 text-sm"
        >
          <div>
            <p class="text-xs font-semibold uppercase text-n-slate-10">
              Status
            </p>
            <div class="mt-2"><CrmStatusBadge :value="lead.status" /></div>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-n-slate-10">
              Responsável
            </p>
            <p class="mt-2 font-semibold text-n-slate-12">
              {{ lead.owner?.name || 'Não atribuído' }}
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-n-slate-10">
              E-mail
            </p>
            <p class="mt-2 break-all text-n-slate-12">
              {{ lead.email || 'Não informado' }}
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-n-slate-10">
              Telefone
            </p>
            <p class="mt-2 text-n-slate-12">
              {{ lead.phone || 'Não informado' }}
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-n-slate-10">
              Canal/origem
            </p>
            <p class="mt-2 font-medium text-n-slate-12">
              {{ lead.source || 'Não informado' }}
            </p>
          </div>
          <div>
            <p class="text-xs font-semibold uppercase text-n-slate-10">
              Equipe
            </p>
            <p class="mt-2 font-medium text-n-slate-12">
              {{ lead.team?.name || 'Não informada' }}
            </p>
          </div>
        </section>
        <section class="mt-5">
          <h4 class="font-bold text-n-slate-12">Anotações</h4>
          <p
            class="mt-2 whitespace-pre-wrap rounded-xl bg-n-alpha-2 p-4 text-sm leading-6 text-n-slate-11"
          >
            {{ lead.notes || 'Nenhuma anotação.' }}
          </p>
        </section>
        <section class="mt-6">
          <h4 class="font-bold text-n-slate-12">Histórico</h4>
          <div v-if="lead.history?.length" class="mt-3 space-y-3">
            <div
              v-for="event in lead.history"
              :key="event.id"
              class="flex gap-3 rounded-xl border border-n-weak p-3"
            >
              <span
                class="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full bg-n-iris-3 text-n-iris-11"
                ><i class="i-lucide-history size-4"
              /></span>
              <div>
                <p class="text-sm font-medium text-n-slate-12">
                  {{ historyText(event) }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ event.created_at_display || formatCrmDateTime(event.created_at) }}
                </p>
              </div>
            </div>
          </div>
          <p
            v-else
            class="mt-3 rounded-xl bg-n-alpha-2 p-4 text-sm text-n-slate-10"
          >
            Nenhuma mudança registrada.
          </p>
        </section>
      </div>
      <footer class="border-t border-n-weak bg-n-alpha-2 p-5">
        <div class="flex flex-wrap gap-2">
          <button
            v-if="lead.conversation"
            type="button"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-3"
            @click="emit('conversation', lead)"
          >
            <i class="i-lucide-message-circle mr-2 inline size-4" />Voltar à
            conversa</button
          ><button
            v-if="lead.contact_id"
            type="button"
            class="rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold text-n-slate-12 hover:bg-n-alpha-3"
            @click="emit('contact', lead)"
          >
            <i class="i-lucide-contact mr-2 inline size-4" />Abrir contato</button
          ><button
            v-if="lead.status === 'converted' && lead.deal_id"
            type="button"
            class="rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white"
            @click="emit('deal', lead)"
          >
            Abrir negócio</button
          ><button
            v-if="['new', 'in_contact'].includes(lead.status)"
            :disabled="saving"
            type="button"
            class="ml-auto rounded-xl bg-n-iris-10 px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
            @click="emit('status-change', lead, 'qualified')"
          >
            Marcar como qualificado</button
          ><button
            v-if="lead.status === 'qualified'"
            type="button"
            class="ml-auto rounded-xl bg-n-teal-10 px-5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-n-teal-11"
            @click="emit('convert', lead)"
          >
            Converter em negócio
          </button>
        </div>
      </footer>
    </aside>
  </div>
</template>
