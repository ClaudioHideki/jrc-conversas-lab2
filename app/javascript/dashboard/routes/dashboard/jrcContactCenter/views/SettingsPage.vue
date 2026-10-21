<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualMetricCard from '../components/visual/VisualMetricCard.vue';
import VisualSectionCard from '../components/visual/VisualSectionCard.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import StructureEditor from './StructureEditor.vue';
import AcwPolicyEditor from '../components/AcwPolicyEditor.vue';

const route = useRoute();
const { t } = useI18n();
const loading = ref(true);
const failed = ref(false);
const units = ref([]);
const queues = ref([]);
const memberships = ref([]);
const rules = ref([]);
const integration = ref(null);
const agents = ref([]);
const context = ref(null);
const accountId = computed(() => route.params.accountId);

const metrics = computed(() => [
  {
    label: t('JRC_CONTACT_CENTER.CARDS.UNITS'),
    value: units.value.length,
    detail: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1154'),
    icon: 'i-lucide-building-2',
    tone: 'blue',
  },
  {
    label: t('JRC_CONTACT_CENTER.CARDS.QUEUES'),
    value: queues.value.length,
    detail: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1155'),
    icon: 'i-lucide-layers-3',
    tone: 'teal',
  },
  {
    label: t('JRC_CONTACT_CENTER.CARDS.MEMBERSHIPS'),
    value: memberships.value.length,
    detail: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1156'),
    icon: 'i-lucide-users-round',
    tone: 'violet',
  },
  {
    label: t('JRC_CONTACT_CENTER.SETTINGS.ROUTING'),
    value: rules.value.length,
    detail: t('JRC_CONTACT_CENTER.VISUAL.LABEL_1157'),
    icon: 'i-lucide-route',
    tone: 'amber',
  },
]);

let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  units.value = [];
  queues.value = [];
  memberships.value = [];
  agents.value = [];
  rules.value = [];
  integration.value = null;
  context.value = null;
  try {
    const responses = await Promise.all([
      JrcContactCenterAPI.units(accountId.value),
      JrcContactCenterAPI.queues(accountId.value),
      JrcContactCenterAPI.queueMemberships(accountId.value),
      JrcContactCenterAPI.routingRules(accountId.value),
      JrcContactCenterAPI.integrationCapabilities(accountId.value),
      JrcContactCenterAPI.context(accountId.value),
    ]);
    if (version !== generation) return;
    units.value = responses[0].data.items || [];
    queues.value = responses[1].data.items || [];
    memberships.value = responses[2].data.items || [];
    agents.value = responses[2].data.agents || [];
    rules.value = responses[3].data.items || [];
    integration.value = responses[4].data;
    context.value = responses[5].data;
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};
watch(accountId, load, { immediate: true });
</script>

<template>
  <div
    class="min-h-full bg-[radial-gradient(circle_at_12%_0%,rgba(8,124,240,.08),transparent_28%)] p-4 sm:p-6"
  >
    <header
      class="relative overflow-hidden rounded-[28px] bg-gradient-to-br from-[#17345f] via-[#23527f] to-[#3f75a7] p-5 text-white shadow-[0_20px_55px_rgba(15,46,82,.22)] sm:p-7"
    >
      <span
        class="pointer-events-none absolute -right-12 -top-24 size-72 rounded-full bg-white/10 blur-3xl"
      />
      <div class="relative flex flex-wrap items-start justify-between gap-4">
        <div class="flex items-start gap-4">
          <span
            class="grid size-12 place-content-center rounded-2xl bg-white/15 ring-1 ring-white/20"
          >
            <Icon icon="i-lucide-settings" class="size-6" />
          </span>
          <div>
            <p
              class="text-xs font-semibold uppercase tracking-[0.18em] text-white/70"
            >
              {{ $t('JRC_CONTACT_CENTER.VISUAL.ESTRUTURA_E_GOVERNANCA') }}
            </p>
            <h1 class="mt-2 text-2xl font-bold tracking-tight sm:text-3xl">
              {{ t('JRC_CONTACT_CENTER.SETTINGS.TITLE') }}
            </h1>
            <p class="mt-2 max-w-3xl text-sm leading-6 text-white/80">
              {{ t('JRC_CONTACT_CENTER.SETTINGS.DESCRIPTION') }}
            </p>
          </div>
        </div>
        <VisualStatusBadge
          :label="
            integration?.provider ||
            t('JRC_CONTACT_CENTER.STATUS.PENDING_CONTRACT')
          "
          tone="amber"
          dot
          class="border-white/25 bg-white/90"
        />
      </div>
    </header>

    <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      <VisualMetricCard
        v-for="item in metrics"
        :key="item.label"
        v-bind="item"
      />
    </div>

    <div
      v-if="failed"
      class="mt-5 rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
    </div>

    <div
      v-if="loading"
      class="mt-5 rounded-2xl border border-n-weak bg-n-solid-2 p-6 text-sm text-n-slate-10"
    >
      {{ t('JRC_CONTACT_CENTER.COMMON.LOADING') }}
    </div>

    <template v-else>
      <AcwPolicyEditor
        v-if="context?.capabilities?.configure"
        :account-id="accountId"
      />
      <VisualSectionCard
        v-if="context?.capabilities?.configure"
        class="mt-5"
        :title="$t('JRC_CONTACT_CENTER.VISUAL.EDITOR_DA_ESTRUTURA_OPERACIONAL')"
        :subtitle="t('JRC_CONTACT_CENTER.SETTINGS.LOCAL_STRUCTURE')"
        icon="i-lucide-network"
      >
        <StructureEditor
          :key="String(accountId)"
          :account-id="accountId"
          :units="units"
          :queues="queues"
          :agents="agents"
          :memberships="memberships"
          @saved="load"
        />
      </VisualSectionCard>

      <div
        class="mt-5 grid gap-5 xl:grid-cols-[minmax(0,1.3fr)_minmax(320px,.7fr)]"
      >
        <VisualSectionCard
          :title="t('JRC_CONTACT_CENTER.SETTINGS.MEMBERSHIPS')"
          :subtitle="
            $t('JRC_CONTACT_CENTER.VISUAL.AGENTES_FILAS_PAPEL_E_SITUACAO')
          "
          icon="i-lucide-users-round"
          flush
        >
          <div
            v-if="memberships.length === 0"
            class="p-5 text-sm text-n-slate-10"
          >
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </div>
          <div v-else class="divide-y divide-n-weak">
            <div
              v-for="membership in memberships"
              :key="membership.id"
              class="flex flex-wrap items-center gap-3 px-4 py-4 sm:px-5"
            >
              <span
                class="grid size-10 shrink-0 place-content-center rounded-full bg-n-iris-2 font-bold text-n-iris-11"
              >
                {{
                  String(membership.user_name || 'A')
                    .slice(0, 1)
                    .toUpperCase()
                }}
              </span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ membership.user_name }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ membership.queue_name
                  }}{{ $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1145')
                  }}{{ membership.role }}
                </p>
              </div>
              <VisualStatusBadge
                :label="
                  membership.active
                    ? t('JRC_CONTACT_CENTER.COMMON.ACTIVE')
                    : t('JRC_CONTACT_CENTER.COMMON.INACTIVE')
                "
                :tone="membership.active ? 'emerald' : 'slate'"
              />
            </div>
          </div>
        </VisualSectionCard>

        <div class="space-y-5">
          <VisualSectionCard
            :title="t('JRC_CONTACT_CENTER.SETTINGS.INTEGRATIONS')"
            :subtitle="
              $t(
                'JRC_CONTACT_CENTER.VISUAL.PROVIDERADAPTER_E_CAPACIDADES_FUTURAS'
              )
            "
            icon="i-lucide-plug-zap"
          >
            <div class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4">
              <p class="text-sm font-semibold text-n-slate-12">
                {{ integration?.provider || 'JRC PABX' }}
              </p>
              <p class="mt-1 text-xs leading-5 text-n-slate-10">
                {{ t('JRC_CONTACT_CENTER.STATUS.PENDING_CONTRACT') }}
              </p>
            </div>
          </VisualSectionCard>

          <VisualSectionCard
            :title="$t('JRC_CONTACT_CENTER.VISUAL.PROXIMAS_INTEGRACOES')"
            :subtitle="
              $t(
                'JRC_CONTACT_CENTER.VISUAL.CAMINHOS_PREPARADOS_SEM_INVENTAR_CONTRATOS'
              )
            "
            icon="i-lucide-route"
          >
            <div class="space-y-3">
              <div
                v-for="item in [
                  'JRC PABX e eventos',
                  'ERP HOYA',
                  'CDR e gravações',
                  'URA e DDD / COE',
                ]"
                :key="item"
                class="flex items-center gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3"
              >
                <span
                  class="grid size-8 place-content-center rounded-lg bg-n-solid-2 text-n-blue-11"
                >
                  <Icon icon="i-lucide-circle-dashed" class="size-4" />
                </span>
                <span class="text-sm font-medium text-n-slate-11">{{
                  item
                }}</span>
              </div>
            </div>
          </VisualSectionCard>
        </div>
      </div>
    </template>
  </div>
</template>
