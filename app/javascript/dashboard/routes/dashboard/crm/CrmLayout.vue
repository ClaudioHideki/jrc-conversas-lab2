<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useResizeObserver } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const route = useRoute();
const store = useStore();
const { t } = useI18n();
const tabList = ref(null);
const canScrollBack = ref(false);
const canScrollForward = ref(false);
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text, @intlify/vue-i18n/no-dynamic-keys */
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
    tone: 'orange',
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
    tone: 'orange',
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
    tone: 'green',
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
    tone: 'green',
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
    tone: 'orange',
  },
  {
    name: 'crm_backoffice',
    label: 'Backoffice',
    icon: 'i-lucide-settings-2',
    tone: 'green',
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

const visibleNavigation = computed(() =>
  navigation.filter(
    item =>
      !['crm_management', 'crm_settings'].includes(item.name) ||
      store.getters.getCurrentRole === 'administrator'
  )
);

const activeTabClass = item => {
  if (route.name !== item.name) return '';
  const tones = {
    blue: 'bg-n-brand',
    cyan: 'bg-cyan-700',
    violet: 'bg-[#6d28d9]',
    orange: 'bg-orange-700',
    green: 'bg-emerald-700',
    rose: 'bg-rose-700',
  };
  return `${tones[item.tone] || tones.blue} border-transparent text-white shadow-sm`;
};

const updateOverflow = () => {
  const element = tabList.value;
  if (!element) return;
  const offset = Math.abs(element.scrollLeft);
  canScrollBack.value = offset > 1;
  canScrollForward.value =
    element.scrollWidth - element.clientWidth - offset > 1;
};
const revealActiveTab = async () => {
  await nextTick();
  const element = tabList.value;
  const activeTab = element?.querySelector('[aria-current="page"]');
  if (activeTab) {
    const listBounds = element.getBoundingClientRect();
    const tabBounds = activeTab.getBoundingClientRect();
    const left =
      tabBounds.left < listBounds.left
        ? tabBounds.left - listBounds.left
        : Math.max(0, tabBounds.right - listBounds.right);
    if (left) element.scrollBy({ left });
  }
  updateOverflow();
};
const scrollTabs = direction => {
  const element = tabList.value;
  const rtl = getComputedStyle(element).direction === 'rtl';
  element.scrollBy({
    left: direction * (rtl ? -1 : 1) * element.clientWidth * 0.75,
  });
};
watch(() => route.name, revealActiveTab);
useResizeObserver(tabList, revealActiveTab);
onMounted(revealActiveTab);
</script>

<template>
  <div
    class="jrc-crm-shell flex h-full min-w-0 flex-1 flex-col bg-n-background text-n-slate-12"
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
      <nav
        class="relative flex min-w-0 items-center gap-2 pb-3"
        :aria-label="t('CRM.NAVIGATION.LABEL')"
      >
        <Button
          v-show="canScrollBack || canScrollForward"
          variant="outline"
          color="slate"
          icon="i-lucide-chevron-left"
          class="shrink-0 rtl:rotate-180"
          :disabled="!canScrollBack"
          :aria-label="t('CRM.NAVIGATION.PREVIOUS')"
          @click="scrollTabs(-1)"
        />
        <div
          ref="tabList"
          class="flex min-w-0 flex-1 gap-2 overflow-x-auto py-1"
          @scroll="updateOverflow"
        >
          <RouterLink
            v-for="item in visibleNavigation"
            :key="item.name"
            :to="{ name: item.name }"
            :aria-current="route.name === item.name ? 'page' : undefined"
            class="jrc-crm-tab flex shrink-0 items-center gap-2 whitespace-nowrap rounded-xl border px-3 py-2.5 text-sm font-medium transition focus-visible:ring-2 focus-visible:ring-n-blue-8"
            :class="
              activeTabClass(item) ||
              'border-n-weak bg-n-solid-2 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12'
            "
          >
            <span
              class="grid size-6 place-content-center rounded-lg bg-n-alpha-1 text-current"
            >
              <Icon :icon="item.icon" class="size-4" />
            </span>
            {{ item.label }}
          </RouterLink>
        </div>
        <Button
          v-show="canScrollBack || canScrollForward"
          variant="outline"
          color="slate"
          icon="i-lucide-chevron-right"
          class="shrink-0 rtl:rotate-180"
          :disabled="!canScrollForward"
          :aria-label="t('CRM.NAVIGATION.NEXT')"
          @click="scrollTabs(1)"
        />
      </nav>
    </header>
    <main class="min-h-0 flex-1 overflow-auto">
      <RouterView :key="route.params.accountId" />
    </main>
  </div>
</template>
