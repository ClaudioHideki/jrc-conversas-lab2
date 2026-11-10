<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ModuleTabs from 'dashboard/components-next/navigation/ModuleTabs.vue';
import ModuleSegmentFilter from '../jrcCustomers/components/ModuleSegmentFilter.vue';
import { crmControlClasses } from './crmControlClasses';
const route = useRoute();
const store = useStore();
const { t } = useI18n();
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
const navigation = [
  {
    name: 'crm_dashboard',
    label: 'Visão Geral',
    icon: 'i-lucide-layout-dashboard',
    tone: 'blue',
  },
  {
    name: 'crm_indicators',
    label: 'Indicadores',
    icon: 'i-lucide-chart-no-axes-combined',
    tone: 'cyan',
  },
  {
    name: 'crm_leads',
    label: 'Leads',
    icon: 'i-lucide-user-round-plus',
    tone: 'violet',
  },
  {
    name: 'crm_deals',
    label: 'Negócios',
    icon: 'i-lucide-handshake',
    tone: 'amber',
  },
  {
    name: 'crm_funnel',
    label: 'Funil',
    icon: 'i-lucide-filter',
    tone: 'violet',
  },
  {
    name: 'crm_wallet',
    label: 'Minha Carteira',
    icon: 'i-lucide-briefcase-business',
    tone: 'blue',
  },
  {
    name: 'crm_activities',
    label: 'Atividades',
    icon: 'i-lucide-calendar-check-2',
    tone: 'amber',
  },
  {
    name: 'crm_calendar',
    label: 'Agenda',
    icon: 'i-lucide-calendar-days',
    tone: 'violet',
  },
  {
    name: 'crm_products',
    label: 'Produtos',
    icon: 'i-lucide-package',
    tone: 'teal',
  },
  {
    name: 'crm_proposals',
    label: 'Propostas',
    icon: 'i-lucide-file-signature',
    tone: 'rose',
  },
  {
    name: 'crm_orders',
    label: 'Pedidos',
    icon: 'i-lucide-shopping-cart',
    tone: 'teal',
  },
  {
    name: 'crm_contracts',
    label: 'Contratos',
    icon: 'i-lucide-file-check-2',
    tone: 'blue',
  },
  { name: 'crm_goals', label: 'Metas', icon: 'i-lucide-target', tone: 'cyan' },
  {
    name: 'crm_commissions',
    label: 'Comissões',
    icon: 'i-lucide-badge-dollar-sign',
    tone: 'amber',
  },
  {
    name: 'crm_management',
    label: 'Gestão de Equipe',
    icon: 'i-lucide-users-round',
    tone: 'violet',
  },
  {
    name: 'crm_settings',
    label: 'Configurações',
    icon: 'i-lucide-settings',
    tone: 'blue',
  },
];

const primaryKeys = [
  'crm_dashboard',
  'crm_indicators',
  'crm_leads',
  'crm_deals',
  'crm_funnel',
];
const visibleNavigation = computed(() =>
  navigation.filter(
    item =>
      !['crm_management', 'crm_settings'].includes(item.name) ||
      store.getters.getCurrentRole === 'administrator'
  )
);
const entry = item => ({ ...item, key: item.name, to: { name: item.name } });
const primary = computed(() =>
  visibleNavigation.value
    .filter(item => primaryKeys.includes(item.name))
    .map(entry)
);
const groups = computed(() =>
  [
    {
      key: 'commercial',
      label: t('CRM.NAVIGATION.COMMERCIAL'),
      icon: 'i-lucide-briefcase-business',
      tone: 'teal',
      keys: [
        'crm_wallet',
        'crm_products',
        'crm_proposals',
        'crm_orders',
        'crm_contracts',
      ],
    },
    {
      key: 'planning',
      label: t('CRM.NAVIGATION.PLANNING'),
      icon: 'i-lucide-calendar-check',
      tone: 'amber',
      keys: ['crm_activities', 'crm_calendar', 'crm_goals', 'crm_commissions'],
    },
    {
      key: 'management',
      label: t('CRM.NAVIGATION.MANAGEMENT'),
      icon: 'i-lucide-settings',
      tone: 'violet',
      keys: ['crm_management', 'crm_settings'],
    },
  ].map(group => ({
    ...group,
    entries: visibleNavigation.value
      .filter(item => group.keys.includes(item.name))
      .map(entry),
  }))
);
const activeKey = computed(
  () =>
    ({
      crm_order_new: 'crm_orders',
      crm_contract_new: 'crm_contracts',
      crm_contract_templates: 'crm_contracts',
    })[route.name] || route.name
);
const supportsCustomerSegment = computed(() =>
  [
    'crm_leads',
    'crm_deals',
    'crm_activities',
    'crm_proposals',
    'crm_orders',
    'crm_contracts',
  ].includes(route.name)
);
</script>

<template>
  <div
    class="jrc-crm-shell flex h-full min-w-0 flex-1 flex-col bg-n-background text-n-slate-12"
    :class="crmControlClasses"
  >
    <header
      class="jrc-crm-top relative shrink-0 border-b border-n-weak bg-n-solid-2 px-4 pt-4 sm:px-6"
    >
      <div
        aria-hidden="true"
        class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_70%_-20%,rgba(139,92,246,.13),transparent_38%),radial-gradient(circle_at_45%_-30%,rgba(8,124,240,.12),transparent_35%)]"
      />
      <div
        class="relative mb-4 flex flex-wrap items-center justify-between gap-4"
      >
        <div class="flex min-w-0 items-center gap-3">
          <span
            class="flex size-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-[#0d8cff] to-[#075fc8] text-white shadow-[0_10px_28px_rgba(8,124,240,0.28)]"
          >
            <i class="i-lucide-chart-no-axes-combined size-5" />
          </span>
          <div class="min-w-0">
            <h1
              class="truncate text-xl font-bold tracking-tight text-n-slate-12"
            >
              CRM Comercial
            </h1>
            <p class="truncate text-xs text-n-slate-11">
              Conversas, oportunidades e relacionamento em um só lugar
            </p>
          </div>
        </div>
        <RouterLink
          :to="{ name: 'crm_leads', query: { new: '1' } }"
          class="inline-flex shrink-0 items-center gap-2 rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:brightness-110 focus-visible:ring-2 focus-visible:ring-n-blue-8"
        >
          <i class="i-lucide-plus size-4" /> Novo lead
        </RouterLink>
      </div>
      <ModuleTabs
        class="relative mb-3"
        :label="t('CRM.NAVIGATION.LABEL')"
        :items="primary"
        :groups="groups"
        :active-key="activeKey"
      />
    </header>
    <ModuleSegmentFilter v-if="supportsCustomerSegment" module-key="crm" />
    <main class="min-h-0 flex-1 overflow-auto">
      <RouterView :key="route.params.accountId" />
    </main>
  </div>
</template>
