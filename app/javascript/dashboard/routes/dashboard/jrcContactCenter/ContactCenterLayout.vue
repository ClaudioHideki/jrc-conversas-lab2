<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';

const route = useRoute();
const { t } = useI18n();
const context = ref(null);
const failed = ref(false);
const mobileNavigationOpen = ref(false);

const accountId = computed(() => route.params.accountId);
const capabilities = computed(() => context.value?.capabilities || {});

const canSupervise = computed(
  () =>
    capabilities.value.supervise === true ||
    capabilities.value.configure === true
);
const canConfigure = computed(() => capabilities.value.configure === true);
const canReport = computed(
  () =>
    capabilities.value.reports === true ||
    capabilities.value.supervise === true ||
    capabilities.value.configure === true
);

const navigationGroups = computed(() => [
  {
    label: t('JRC_CONTACT_CENTER.NAV_GROUPS.AGENT'),
    items: [
      {
        name: 'jrc_contact_center_cockpit',
        label: t('JRC_CONTACT_CENTER.NAV.COCKPIT'),
        icon: 'i-lucide-headphones',
        visible: true,
      },
      {
        name: 'jrc_contact_center_call',
        label: t('JRC_CONTACT_CENTER.NAV.CALL'),
        icon: 'i-lucide-phone-call',
        visible: true,
      },
      {
        name: 'jrc_contact_center_after_call',
        label: t('JRC_CONTACT_CENTER.NAV.AFTER_CALL'),
        icon: 'i-lucide-clipboard-check',
        visible: true,
      },
      {
        name: 'jrc_contact_center_customer_360',
        label: t('JRC_CONTACT_CENTER.NAV.CUSTOMER_360'),
        icon: 'i-lucide-orbit',
        visible: true,
      },
    ],
  },
  {
    label: t('JRC_CONTACT_CENTER.NAV_GROUPS.SUPERVISOR'),
    items: [
      {
        name: 'jrc_contact_center_supervisor',
        label: t('JRC_CONTACT_CENTER.NAV.SUPERVISOR'),
        icon: 'i-lucide-monitor-dot',
        visible: canSupervise.value,
      },
      {
        name: 'jrc_contact_center_finance',
        label: t('JRC_CONTACT_CENTER.NAV.FINANCE'),
        icon: 'i-lucide-landmark',
        visible: canSupervise.value,
      },
      {
        name: 'jrc_contact_center_coes',
        label: t('JRC_CONTACT_CENTER.NAV.COES'),
        icon: 'i-lucide-map',
        visible: canSupervise.value,
      },
    ],
  },
  {
    label: t('JRC_CONTACT_CENTER.NAV_GROUPS.CONTROL_DESK'),
    items: [
      {
        name: 'jrc_contact_center_control_desk',
        label: t('JRC_CONTACT_CENTER.NAV.CONTROL_DESK'),
        icon: 'i-lucide-radar',
        visible: canSupervise.value,
      },
      {
        name: 'jrc_contact_center_order_lookup',
        label: t('JRC_CONTACT_CENTER.NAV.ORDER_LOOKUP'),
        icon: 'i-lucide-package-search',
        visible: canSupervise.value,
      },
      {
        name: 'jrc_contact_center_pabx',
        label: t('JRC_CONTACT_CENTER.NAV.PABX'),
        icon: 'i-lucide-server-cog',
        visible: canSupervise.value,
      },
      {
        name: 'jrc_contact_center_migration',
        label: t('JRC_CONTACT_CENTER.NAV.MIGRATION'),
        icon: 'i-lucide-workflow',
        visible: canConfigure.value,
      },
    ],
  },
  {
    label: t('JRC_CONTACT_CENTER.NAV_GROUPS.MONITORING'),
    items: [
      {
        name: 'jrc_contact_center_recordings',
        label: t('JRC_CONTACT_CENTER.NAV.RECORDINGS'),
        icon: 'i-lucide-audio-waveform',
        visible: canReport.value,
      },
      {
        name: 'jrc_contact_center_reports',
        label: t('JRC_CONTACT_CENTER.NAV.REPORTS'),
        icon: 'i-lucide-chart-no-axes-combined',
        visible: canReport.value,
      },
      {
        name: 'jrc_contact_center_surveys',
        label: t('JRC_CONTACT_CENTER.NAV.SURVEYS'),
        icon: 'i-lucide-message-circle-heart',
        visible: canReport.value,
      },
    ],
  },
  {
    label: t('JRC_CONTACT_CENTER.NAV_GROUPS.SETTINGS'),
    items: [
      {
        name: 'jrc_contact_center_settings',
        label: t('JRC_CONTACT_CENTER.NAV.SETTINGS'),
        icon: 'i-lucide-settings',
        visible: canConfigure.value,
      },
      {
        name: 'jrc_contact_center_ivr',
        label: t('JRC_CONTACT_CENTER.NAV.IVR'),
        icon: 'i-lucide-git-branch',
        visible: canConfigure.value,
      },
      {
        name: 'ramal_index',
        label: t('JRC_CONTACT_CENTER.NAV.EXTENSIONS'),
        icon: 'i-lucide-phone',
        visible: canConfigure.value,
      },
      {
        name: 'jrc_contact_center_security',
        label: t('JRC_CONTACT_CENTER.NAV.SECURITY'),
        icon: 'i-lucide-shield-check',
        visible: canConfigure.value,
      },
    ],
  },
]);

const visibleGroups = computed(() =>
  navigationGroups.value
    .map(group => ({
      ...group,
      items: group.items.filter(item => item.visible),
    }))
    .filter(group => group.items.length)
);

const activeItem = computed(() =>
  visibleGroups.value
    .flatMap(group => group.items)
    .find(item => item.name === route.name)
);

let generation = 0;
watch(
  accountId,
  async id => {
    generation += 1;
    const version = generation;
    context.value = null;
    failed.value = false;
    mobileNavigationOpen.value = false;
    try {
      const { data } = await JrcContactCenterAPI.context(id);
      if (version === generation) context.value = data;
    } catch {
      if (version === generation) failed.value = true;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div v-if="context" class="flex h-full min-h-0 flex-col bg-n-background">
    <header
      class="relative shrink-0 overflow-hidden border-b border-n-weak bg-n-solid-2 px-4 py-4 sm:px-6"
    >
      <div
        aria-hidden="true"
        class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_12%_-30%,rgba(8,124,240,.18),transparent_35%),radial-gradient(circle_at_80%_-50%,rgba(124,58,237,.14),transparent_35%)]"
      />
      <div class="relative flex flex-wrap items-center justify-between gap-4">
        <div class="flex min-w-0 items-center gap-3">
          <span
            class="grid size-12 shrink-0 place-content-center rounded-2xl bg-gradient-to-br from-[#0a79e8] via-[#087cf0] to-[#53b9ff] text-white shadow-[0_10px_28px_rgba(8,124,240,.28)]"
          >
            <Icon icon="i-lucide-headphones" class="size-6" />
          </span>
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <h1
                class="truncate text-xl font-bold tracking-tight text-n-slate-12"
              >
                {{ t('JRC_CONTACT_CENTER.TITLE') }}
              </h1>
              <span
                class="rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide text-emerald-700"
              >
                {{ t('JRC_CONTACT_CENTER.STATUS.NATIVE_OPERATION') }}
              </span>
            </div>
            <p class="mt-1 truncate text-xs text-n-slate-10">
              {{ t('JRC_CONTACT_CENTER.SUBTITLE') }}
            </p>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <span
            class="hidden rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs font-semibold text-n-slate-11 shadow-sm sm:inline-flex"
          >
            {{ activeItem?.label || t('JRC_CONTACT_CENTER.NAV.COCKPIT') }}
          </span>
          <button
            type="button"
            class="inline-flex items-center gap-2 rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm font-semibold text-n-slate-11 shadow-sm xl:hidden"
            :aria-expanded="mobileNavigationOpen"
            @click="mobileNavigationOpen = !mobileNavigationOpen"
          >
            <Icon icon="i-lucide-menu" class="size-4" />
            {{ t('JRC_CONTACT_CENTER.COMMON.NAVIGATION') }}
          </button>
        </div>
      </div>
    </header>

    <div class="flex min-h-0 flex-1 flex-col xl:flex-row">
      <aside
        class="border-b border-n-weak bg-n-solid-2 xl:w-64 xl:shrink-0 xl:border-b-0 xl:border-r"
        :class="mobileNavigationOpen ? 'block' : 'hidden xl:block'"
      >
        <nav class="max-h-[42vh] overflow-auto p-3 xl:max-h-none xl:p-4">
          <section
            v-for="group in visibleGroups"
            :key="group.label"
            class="mb-5 last:mb-0"
          >
            <p
              class="px-3 pb-1 text-[10px] font-bold uppercase tracking-[0.16em] text-n-slate-9"
            >
              {{ group.label }}
            </p>
            <div class="space-y-1">
              <RouterLink
                v-for="item in group.items"
                :key="item.name"
                :to="{ name: item.name, params: { accountId } }"
                class="flex items-center gap-2.5 rounded-xl px-3 py-2.5 text-sm font-medium text-n-slate-11 transition hover:bg-n-alpha-2 hover:text-n-slate-12"
                active-class="bg-n-blue-2 text-n-blue-11 shadow-sm ring-1 ring-n-blue-5"
                @click="mobileNavigationOpen = false"
              >
                <span
                  class="grid size-8 shrink-0 place-content-center rounded-lg bg-n-alpha-1 text-current"
                >
                  <Icon :icon="item.icon" class="size-4" />
                </span>
                <span class="truncate">{{ item.label }}</span>
              </RouterLink>
            </div>
          </section>
        </nav>
      </aside>
      <main class="min-h-0 min-w-0 flex-1 overflow-auto">
        <RouterView :key="`${accountId}-${route.name}`" />
      </main>
    </div>
  </div>
  <div v-else class="p-6 text-sm text-n-slate-11" role="status">
    <p v-if="failed" role="alert">
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </p>
    <p v-else>{{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}</p>
  </div>
</template>
