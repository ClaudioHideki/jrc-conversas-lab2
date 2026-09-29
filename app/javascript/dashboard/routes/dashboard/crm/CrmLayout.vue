<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';

const route = useRoute();
const store = useStore();
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text, @intlify/vue-i18n/no-dynamic-keys */
const navigation = [
  { name: 'crm_dashboard', label: 'Visão Geral', icon: 'i-lucide-layout-dashboard', tone: 'blue' },
  { name: 'crm_indicators', label: 'Indicadores', icon: 'i-lucide-chart-no-axes-combined', tone: 'cyan' },
  { name: 'crm_leads', label: 'Leads', icon: 'i-lucide-user-round-plus', tone: 'violet' },
  { name: 'crm_deals', label: 'Negócios', icon: 'i-lucide-handshake', tone: 'orange' },
  { name: 'crm_funnel', label: 'Funil', icon: 'i-lucide-filter', tone: 'violet' },
  { name: 'crm_wallet', label: 'Minha Carteira', icon: 'i-lucide-briefcase-business', tone: 'blue' },
  { name: 'crm_activities', label: 'Atividades', icon: 'i-lucide-calendar-check-2', tone: 'orange' },
  { name: 'crm_calendar', label: 'Agenda', icon: 'i-lucide-calendar-days', tone: 'violet' },
  { name: 'crm_products', label: 'Produtos', icon: 'i-lucide-package', tone: 'green' },
  { name: 'crm_proposals', label: 'Propostas', icon: 'i-lucide-file-signature', tone: 'rose' },
  { name: 'crm_orders', label: 'Pedidos', icon: 'i-lucide-shopping-cart', tone: 'green' },
  { name: 'crm_contracts', label: 'Contratos', icon: 'i-lucide-file-check-2', tone: 'blue' },
  { name: 'crm_goals', label: 'Metas', icon: 'i-lucide-target', tone: 'cyan' },
  { name: 'crm_commissions', label: 'Comissões', icon: 'i-lucide-badge-dollar-sign', tone: 'orange' },
  { name: 'crm_backoffice', label: 'Backoffice', icon: 'i-lucide-settings-2', tone: 'green' },
  { name: 'crm_management', label: 'Gestão de Equipe', icon: 'i-lucide-users-round', tone: 'violet' },
  { name: 'crm_settings', label: 'Configurações', icon: 'i-lucide-settings', tone: 'blue' },
];

const visibleNavigation = computed(() => navigation.filter(item =>
  !['crm_management', 'crm_settings'].includes(item.name) || store.getters.getCurrentRole === 'administrator'
));

const activeTabClass = item => {
  if (route.name !== item.name) return '';
  const tones = {
    blue: '!border-transparent !bg-[#087cf0] !text-white !shadow-[0_8px_22px_rgba(8,124,240,.24)]',
    cyan: '!border-transparent !bg-[#0ea5b7] !text-white !shadow-[0_8px_22px_rgba(14,165,183,.22)]',
    violet: '!border-transparent !bg-[#7c3aed] !text-white !shadow-[0_8px_22px_rgba(124,58,237,.24)]',
    orange: '!border-transparent !bg-[#f97316] !text-white !shadow-[0_8px_22px_rgba(249,115,22,.22)]',
    green: '!border-transparent !bg-[#16a76b] !text-white !shadow-[0_8px_22px_rgba(22,167,107,.22)]',
    rose: '!border-transparent !bg-[#e83b6a] !text-white !shadow-[0_8px_22px_rgba(232,59,106,.22)]',
  };
  return tones[item.tone] || tones.blue;
};

</script>

<template>
  <div class="jrc-crm-shell flex h-full min-w-0 flex-1 flex-col bg-[#f7f9fc]">
    <header class="jrc-crm-top relative shrink-0 overflow-hidden border-b border-[#e7ebf2] bg-white px-4 pt-4 sm:px-6">
      <div aria-hidden="true" class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_70%_-20%,rgba(139,92,246,.13),transparent_38%),radial-gradient(circle_at_45%_-30%,rgba(8,124,240,.12),transparent_35%)]" />
      <div class="relative mb-4 flex flex-wrap items-center justify-between gap-4">
        <div class="flex min-w-0 items-center gap-3">
          <span class="flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-[#0d8cff] to-[#075fc8] text-white shadow-[0_10px_28px_rgba(8,124,240,0.28)]">
            <i class="i-lucide-chart-no-axes-combined size-5" />
          </span>
          <div class="min-w-0">
            <h1 class="truncate text-xl font-bold tracking-tight text-[#172033]">CRM Comercial</h1>
            <p class="truncate text-xs text-[#6f7c91]">Conversas, oportunidades e relacionamento em um só lugar</p>
          </div>
        </div>
        <RouterLink :to="{ name: 'crm_leads', query: { new: '1' } }" class="inline-flex shrink-0 items-center gap-2 rounded-xl bg-[#087cf0] px-4 py-2.5 text-sm font-semibold text-white shadow-[0_8px_20px_rgba(8,124,240,.26)] transition hover:-translate-y-0.5 hover:bg-[#056ed8]">
          <i class="i-lucide-plus size-4" /> Novo lead
        </RouterLink>
      </div>
      <nav class="relative flex min-w-0 gap-2 overflow-x-auto pb-3 [scrollbar-width:none]">
        <RouterLink v-for="item in visibleNavigation" :key="item.name" :to="{ name: item.name }" class="jrc-crm-tab flex items-center gap-2 whitespace-nowrap rounded-xl border border-[#e8ecf2] bg-white px-3 py-2.5 text-sm font-medium text-[#4a5568] shadow-[0_2px_8px_rgba(16,24,40,.04)] transition hover:-translate-y-0.5 hover:border-[#cfd7e4] hover:text-[#172033]" :class="activeTabClass(item)">
          <span class="grid size-6 place-content-center rounded-lg bg-black/[.035] text-current"><i class="size-4" :class="item.icon" /></span>
          {{ item.label }}
        </RouterLink>
      </nav>
    </header>
    <main class="min-h-0 flex-1 overflow-auto">
      <RouterView :key="route.params.accountId" />
    </main>
  </div>
</template>

<style>
.jrc-crm-shell { color-scheme: light; }
.jrc-crm-shell main { background: radial-gradient(circle at 82% 0%,rgba(124,58,237,.055),transparent 28%), radial-gradient(circle at 45% 0%,rgba(8,124,240,.07),transparent 34%), linear-gradient(180deg,#f7faff 0,#f1f5fb 48%,#f7f9fc 100%); }
.jrc-crm-shell main > div > div { max-width: 1680px !important; }
.jrc-crm-shell article,
.jrc-crm-shell .shadow-sm { box-shadow: 0 8px 24px rgba(15, 23, 42, .055) !important; }
.jrc-crm-shell .rounded-2xl { border-radius: 16px !important; }
.jrc-crm-shell input,
.jrc-crm-shell select,
.jrc-crm-shell textarea { border-color: #e3e8ef !important; background-color: #fff !important; }
.jrc-crm-shell table thead { background: #f8fafc !important; }
.jrc-crm-shell table tbody tr:hover { background: #f8fbff !important; }
.jrc-crm-tab--active span { background: rgba(255,255,255,.14) !important; }
@media (max-width: 900px) {
  .jrc-crm-top { padding-left: 14px !important; padding-right: 14px !important; }
}
</style>
