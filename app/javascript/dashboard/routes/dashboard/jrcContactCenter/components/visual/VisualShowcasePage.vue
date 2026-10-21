<script setup>
import { useI18n } from 'vue-i18n';
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import VisualMetricCard from './VisualMetricCard.vue';
import VisualStatusBadge from './VisualStatusBadge.vue';
import VisualSectionCard from './VisualSectionCard.vue';
import VisualTimeline from './VisualTimeline.vue';
import VisualMiniBars from './VisualMiniBars.vue';
import VisualProgress from './VisualProgress.vue';

const props = defineProps({
  screen: { type: Object, required: true },
  compact: { type: Boolean, default: false },
  showDemoBadge: { type: Boolean, default: true },
});

const route = useRoute();

const accentClasses = {
  blue: {
    hero: 'from-[#0a6fdc] via-[#0b82ee] to-[#59b9ff]',
    icon: 'bg-white/20 text-white',
    glow: 'bg-[#a7ddff]/30',
  },
  teal: {
    hero: 'from-[#056b75] via-[#078f9c] to-[#4cc9bf]',
    icon: 'bg-white/20 text-white',
    glow: 'bg-[#b2f5ea]/25',
  },
  violet: {
    hero: 'from-[#4f2aa8] via-[#7048d7] to-[#a78bfa]',
    icon: 'bg-white/20 text-white',
    glow: 'bg-[#ddd6fe]/25',
  },
  ruby: {
    hero: 'from-[#8f1d3f] via-[#be2f57] to-[#fb7185]',
    icon: 'bg-white/20 text-white',
    glow: 'bg-[#fecdd3]/25',
  },
  amber: {
    hero: 'from-[#9a4b06] via-[#d97706] to-[#fbbf24]',
    icon: 'bg-white/20 text-white',
    glow: 'bg-[#fde68a]/25',
  },
};

const accent = computed(
  () => accentClasses[props.screen.accent] || accentClasses.blue
);

const actionClasses = {
  primary: 'bg-white text-[#0a5fc2] hover:bg-white/90',
  secondary: 'border border-white/25 bg-white/10 text-white hover:bg-white/15',
  danger: 'bg-[#d92d4b] text-white hover:bg-[#c41f3e]',
};

const actionTarget = item => ({
  name: item.routeName,
  params: { accountId: route.params.accountId, ...(item.params || {}) },
  query: item.query || {},
});

const { t } = useI18n();

const visualBadgeLabel = computed(() =>
  t('JRC_CONTACT_CENTER.VISUAL.HOYA_360_DEMONSTRACAO')
);
</script>

<template>
  <div
    class="min-h-full bg-[radial-gradient(circle_at_12%_0%,rgba(8,124,240,.08),transparent_26%),radial-gradient(circle_at_92%_8%,rgba(124,58,237,.08),transparent_22%)]"
    :class="compact ? 'p-3 sm:p-4' : 'p-4 sm:p-6'"
  >
    <header
      class="relative overflow-hidden rounded-[28px] bg-gradient-to-br p-5 text-white shadow-[0_20px_55px_rgba(15,46,82,.22)] sm:p-6 lg:p-7"
      :class="accent.hero"
    >
      <span
        class="pointer-events-none absolute -right-16 -top-24 size-72 rounded-full blur-3xl"
        :class="accent.glow"
      />
      <span
        class="pointer-events-none absolute -bottom-36 left-1/3 size-80 rounded-full bg-white/10 blur-3xl"
      />
      <div class="relative flex flex-wrap items-start justify-between gap-5">
        <div class="flex min-w-0 items-start gap-4">
          <span
            class="grid size-12 shrink-0 place-content-center rounded-2xl shadow-inner ring-1 ring-white/20 sm:size-14"
            :class="accent.icon"
          >
            <Icon :icon="screen.icon" class="size-6 sm:size-7" />
          </span>
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <p
                class="text-xs font-semibold uppercase tracking-[0.18em] text-white/75"
              >
                {{ screen.eyebrow }}
              </p>
              <span
                v-if="showDemoBadge"
                class="rounded-full border border-white/20 bg-white/10 px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wide text-white/80"
              >
                {{ visualBadgeLabel }}
              </span>
            </div>
            <h1
              class="mt-2 text-2xl font-bold tracking-tight text-white sm:text-3xl"
            >
              {{ screen.title }}
            </h1>
            <p
              class="mt-2 max-w-3xl text-sm leading-6 text-white/80 sm:text-base"
            >
              {{ screen.description }}
            </p>
          </div>
        </div>
        <VisualStatusBadge
          v-if="screen.status"
          :label="screen.status.label"
          :tone="screen.status.tone"
          dot
          class="border-white/25 bg-white/90 shadow-sm"
        />
      </div>

      <div
        v-if="screen.actions?.length"
        class="relative mt-6 flex flex-wrap gap-2"
      >
        <RouterLink
          v-for="item in screen.actions?.filter(
            actionItem => actionItem.routeName
          ) || []"
          :key="`route-${item.label}`"
          :to="actionTarget(item)"
          class="inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold shadow-sm transition focus-visible:ring-2 focus-visible:ring-white/70"
          :class="actionClasses[item.tone] || actionClasses.primary"
        >
          <Icon :icon="item.icon" class="size-4" />
          {{ item.label }}
        </RouterLink>
        <button
          v-for="item in screen.actions?.filter(
            actionItem => !actionItem.routeName
          ) || []"
          :key="`button-${item.label}`"
          type="button"
          class="inline-flex items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold shadow-sm transition focus-visible:ring-2 focus-visible:ring-white/70"
          :class="actionClasses[item.tone] || actionClasses.primary"
        >
          <Icon :icon="item.icon" class="size-4" />
          {{ item.label }}
        </button>
      </div>
    </header>

    <div
      v-if="screen.metrics?.length"
      class="mt-5 grid gap-3 sm:grid-cols-2 2xl:grid-cols-4"
    >
      <VisualMetricCard
        v-for="item in screen.metrics"
        :key="item.label"
        v-bind="item"
      />
    </div>

    <VisualSectionCard
      v-if="screen.flow?.length"
      class="mt-5"
      :title="$t('JRC_CONTACT_CENTER.VISUAL.JORNADA_VISUAL')"
      :subtitle="
        $t(
          'JRC_CONTACT_CENTER.VISUAL.FLUXO_ILUSTRATIVO_PREPARADO_PARA_CONTRATOS_E_APIS_FUTUR'
        )
      "
      icon="i-lucide-workflow"
    >
      <div class="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
        <div
          v-for="(node, index) in screen.flow"
          :key="node.title"
          class="relative rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
        >
          <div class="flex items-start gap-3">
            <span
              class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11"
            >
              <Icon :icon="node.icon" class="size-5" />
            </span>
            <div>
              <p class="text-sm font-semibold text-n-slate-12">
                {{ node.title }}
              </p>
              <p class="mt-1 text-xs leading-5 text-n-slate-10">
                {{ node.detail }}
              </p>
            </div>
          </div>
          <span
            v-if="index < screen.flow.length - 1"
            class="absolute -right-2 top-1/2 hidden size-4 -translate-y-1/2 place-content-center rounded-full bg-n-solid-2 text-n-slate-8 shadow-sm xl:grid"
          >
            <Icon icon="i-lucide-chevron-right" class="size-3" />
          </span>
        </div>
      </div>
    </VisualSectionCard>

    <div
      class="mt-5 grid gap-5 xl:grid-cols-[minmax(0,1.6fr)_minmax(280px,.8fr)]"
    >
      <VisualSectionCard
        :title="screen.primary?.title || screen.title"
        :subtitle="screen.primary?.subtitle || screen.description"
        :icon="screen.icon"
        flush
      >
        <div class="divide-y divide-n-weak">
          <div
            v-for="(item, index) in screen.primary?.items || []"
            :key="item.id || `${item.title}-${index}`"
            class="group flex flex-wrap items-center gap-3 px-4 py-4 transition hover:bg-n-alpha-1 sm:px-5"
          >
            <span
              class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11 transition group-hover:scale-105"
            >
              <Icon :icon="item.icon || 'i-lucide-circle-dot'" class="size-5" />
            </span>
            <div class="min-w-0 flex-1">
              <p class="text-sm font-semibold text-n-slate-12">
                {{ item.title }}
              </p>
              <p class="mt-1 text-xs leading-5 text-n-slate-10">
                {{ item.description }}
              </p>
            </div>
            <div class="ml-auto flex shrink-0 items-center gap-2">
              <span
                v-if="item.meta"
                class="hidden text-xs text-n-slate-9 sm:inline"
              >
                {{ item.meta }}
              </span>
              <VisualStatusBadge
                v-if="item.status"
                :label="item.status"
                :tone="item.tone || 'slate'"
              />
            </div>
          </div>
        </div>
      </VisualSectionCard>

      <div class="space-y-5">
        <VisualSectionCard
          v-if="screen.secondary"
          :title="screen.secondary.title"
          icon="i-lucide-sparkles"
        >
          <div class="space-y-3">
            <div
              v-for="item in screen.secondary.items || []"
              :key="item.title"
              class="flex gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3.5"
            >
              <span
                class="grid size-9 shrink-0 place-content-center rounded-xl bg-n-solid-2 text-n-blue-11 shadow-sm"
              >
                <Icon
                  :icon="item.icon || 'i-lucide-circle-dot'"
                  class="size-4"
                />
              </span>
              <div>
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ item.title }}
                </p>
                <p class="mt-1 text-xs leading-5 text-n-slate-10">
                  {{ item.description }}
                </p>
              </div>
            </div>
          </div>
        </VisualSectionCard>

        <VisualSectionCard
          v-if="screen.progress?.length"
          :title="$t('JRC_CONTACT_CENTER.VISUAL.INDICADORES_CHAVE')"
          :subtitle="
            $t('JRC_CONTACT_CENTER.VISUAL.METAS_E_EVOLUCAO_DA_OPERACAO')
          "
          icon="i-lucide-gauge"
        >
          <div class="space-y-4">
            <VisualProgress
              v-for="item in screen.progress"
              :key="item.label"
              v-bind="item"
            />
          </div>
        </VisualSectionCard>

        <VisualSectionCard
          v-if="screen.chart?.length"
          :title="$t('JRC_CONTACT_CENTER.VISUAL.TENDENCIA')"
          :subtitle="$t('JRC_CONTACT_CENTER.VISUAL.SERIE_VISUAL_DEMONSTRATIVA')"
          icon="i-lucide-chart-spline"
        >
          <VisualMiniBars :values="screen.chart" :tone="screen.accent" />
          <div
            class="mt-3 flex justify-between text-[10px] font-medium uppercase tracking-wide text-n-slate-9"
          >
            <span>{{ $t('JRC_CONTACT_CENTER.VISUAL.INICIO') }}</span>
            <span>{{ $t('JRC_CONTACT_CENTER.VISUAL.AGORA') }}</span>
          </div>
        </VisualSectionCard>
      </div>
    </div>

    <VisualSectionCard
      v-if="screen.phases?.length"
      class="mt-5"
      :title="$t('JRC_CONTACT_CENTER.VISUAL.ONDAS_E_MARCOS')"
      :subtitle="
        $t(
          'JRC_CONTACT_CENTER.VISUAL.AVANCO_CONTROLADO_COM_EVIDENCIAS_E_ROLLBACK'
        )
      "
      icon="i-lucide-milestone"
    >
      <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
        <article
          v-for="(phase, index) in screen.phases"
          :key="phase.title"
          class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
        >
          <div class="flex items-center justify-between gap-3">
            <span
              class="grid size-8 place-content-center rounded-lg bg-n-solid-2 text-xs font-bold text-n-blue-11"
            >
              {{ String(index + 1).padStart(2, '0') }}
            </span>
            <VisualStatusBadge :label="phase.state" :tone="phase.tone" />
          </div>
          <h3 class="mt-4 text-sm font-semibold text-n-slate-12">
            {{ phase.title }}
          </h3>
          <p class="mt-1 text-xs leading-5 text-n-slate-10">
            {{ phase.detail }}
          </p>
        </article>
      </div>
    </VisualSectionCard>

    <VisualSectionCard
      v-if="screen.timeline?.length"
      class="mt-5"
      :title="$t('JRC_CONTACT_CENTER.VISUAL.TIMELINE_INTEGRADA')"
      :subtitle="
        $t(
          'JRC_CONTACT_CENTER.VISUAL.CRM_CONTACT_CENTER_PEDIDOS_E_ATIVIDADES_NO_MESMO_HISTOR'
        )
      "
      icon="i-lucide-history"
    >
      <VisualTimeline :items="screen.timeline" />
    </VisualSectionCard>
  </div>
</template>
