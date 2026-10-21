<script setup>
import { useI18n } from 'vue-i18n';
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualShowcasePage from '../components/visual/VisualShowcasePage.vue';
import VisualSectionCard from '../components/visual/VisualSectionCard.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import { contactCenterScreen } from '../demo/contactCenterVisualCatalog';

const { t } = useI18n();

const route = useRoute();
const loading = ref(true);
const failed = ref(false);
const metrics = ref({});
const accountId = computed(() => route.params.accountId);

const reportScreen = computed(() => {
  const source = contactCenterScreen('reports', t);
  const values = [
    metrics.value.offered_count,
    metrics.value.abandoned_count,
    metrics.value.tma_seconds
      ? `${Math.floor(metrics.value.tma_seconds / 60)
          .toString()
          .padStart(2, '0')}:${(metrics.value.tma_seconds % 60)
          .toString()
          .padStart(2, '0')}`
      : null,
    metrics.value.nps_score,
  ];
  return {
    ...source,
    metrics: source.metrics.map((item, index) => ({
      ...item,
      value: values[index] ?? item.value,
    })),
  };
});

const operationalRows = computed(() => [
  [
    t('JRC_CONTACT_CENTER.VISUAL.OFERECIDAS'),
    metrics.value.offered_count || 0,
    'blue',
  ],
  [
    t('JRC_CONTACT_CENTER.VISUAL.ATENDIDAS'),
    metrics.value.answered_count || 0,
    'emerald',
  ],
  [
    t('JRC_CONTACT_CENTER.VISUAL.ABANDONADAS'),
    metrics.value.abandoned_count || 0,
    'ruby',
  ],
  [
    t('JRC_CONTACT_CENTER.VISUAL.TRANSFERIDAS'),
    metrics.value.transferred_count || 0,
    'violet',
  ],
  [
    t('JRC_CONTACT_CENTER.VISUAL.FALLBACK_COE_SAC'),
    metrics.value.fallback_count || 0,
    'amber',
  ],
]);

let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await JrcContactCenterAPI.reportSummary(accountId.value);
    if (version === generation) metrics.value = data.metrics || {};
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(accountId, load, { immediate: true });
</script>

<template>
  <div>
    <VisualShowcasePage :screen="reportScreen" />

    <section class="space-y-5 px-4 pb-6 sm:px-6">
      <div
        v-if="failed"
        class="rounded-2xl border border-n-amber-6 bg-n-amber-2 p-4 text-sm text-n-amber-11"
      >
        {{
          $t(
            'JRC_CONTACT_CENTER.VISUAL.A_PROJECAO_VISUAL_PERMANECE_DISPONIVEL_OS_DADOS_NATIVOS'
          )
        }}
      </div>

      <div class="grid gap-5 xl:grid-cols-[minmax(0,1.3fr)_minmax(320px,.7fr)]">
        <VisualSectionCard
          :title="$t('JRC_CONTACT_CENTER.VISUAL.RESUMO_OPERACIONAL_NATIVO')"
          :subtitle="
            loading
              ? $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1146')
              : $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1147')
          "
          icon="i-lucide-chart-column"
          flush
        >
          <div class="divide-y divide-n-weak">
            <div
              v-for="[label, value, tone] in operationalRows"
              :key="label"
              class="flex items-center justify-between gap-3 px-4 py-4 sm:px-5"
            >
              <span class="text-sm font-medium text-n-slate-11">{{
                label
              }}</span>
              <VisualStatusBadge :label="String(value)" :tone="tone" />
            </div>
          </div>
        </VisualSectionCard>

        <VisualSectionCard
          :title="$t('JRC_CONTACT_CENTER.VISUAL.FILTROS_E_EXPORTACAO')"
          :subtitle="
            $t(
              'JRC_CONTACT_CENTER.VISUAL.ESTRUTURA_VISUAL_PREPARADA_PARA_A_CAMADA_DE_BI'
            )
          "
          icon="i-lucide-filter"
        >
          <div class="space-y-3">
            <label class="block">
              <span class="text-xs font-semibold text-n-slate-10">{{
                $t('JRC_CONTACT_CENTER.VISUAL.PERIODO')
              }}</span>
              <select
                class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-12"
              >
                <option>
                  {{ $t('JRC_CONTACT_CENTER.VISUAL.ULTIMOS_30_DIAS') }}
                </option>
                <option>{{ $t('JRC_CONTACT_CENTER.VISUAL.HOJE') }}</option>
                <option>
                  {{ $t('JRC_CONTACT_CENTER.VISUAL.ESTA_SEMANA') }}
                </option>
              </select>
            </label>
            <label class="block">
              <span class="text-xs font-semibold text-n-slate-10">{{
                $t('JRC_CONTACT_CENTER.VISUAL.UNIDADE_FILA')
              }}</span>
              <select
                class="mt-1.5 w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-12"
              >
                <option>
                  {{
                    $t(
                      'JRC_CONTACT_CENTER.VISUAL.TODAS_AS_UNIDADES_AUTORIZADAS'
                    )
                  }}
                </option>
                <option>
                  {{ $t('JRC_CONTACT_CENTER.VISUAL.SAC_NACIONAL') }}
                </option>
                <option>
                  {{ $t('JRC_CONTACT_CENTER.VISUAL.FINANCEIRO') }}
                </option>
              </select>
            </label>
            <div class="grid grid-cols-2 gap-2 pt-1">
              <button
                class="rounded-xl bg-n-brand px-3 py-2.5 text-sm font-semibold text-white"
              >
                {{ $t('JRC_CONTACT_CENTER.VISUAL.APLICAR') }}
              </button>
              <button
                class="rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm font-semibold text-n-slate-11"
              >
                {{ $t('JRC_CONTACT_CENTER.VISUAL.EXPORTAR') }}
              </button>
            </div>
          </div>
        </VisualSectionCard>
      </div>
    </section>
  </div>
</template>
