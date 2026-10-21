<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualShowcasePage from '../components/visual/VisualShowcasePage.vue';
import VisualSectionCard from '../components/visual/VisualSectionCard.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import { contactCenterScreen } from '../demo/contactCenterVisualCatalog';

const route = useRoute();
const { t } = useI18n();
const loading = ref(true);
const failed = ref(false);
const integration = ref(null);
const health = ref(null);
const events = ref([]);
const reprocessing = ref(false);
const accountId = computed(() => route.params.accountId);
const capabilityRows = computed(() =>
  Object.entries(integration.value?.capabilities || {})
);

const controlDeskScreen = computed(() => {
  const source = contactCenterScreen('controlDesk', t);
  const eventStatuses = health.value?.events?.statuses || {};
  const commandStatuses = health.value?.commands?.statuses || {};
  const eventTotal = Object.values(eventStatuses).reduce(
    (total, count) => total + Number(count || 0),
    0
  );
  const alertCount =
    Number(health.value?.events?.unverified || 0) +
    Number(eventStatuses.failed || 0) +
    Number(commandStatuses.unknown || 0);
  const metrics = source.metrics.map((item, index) => {
    const values = [
      item.value,
      item.value,
      alertCount || item.value,
      eventTotal ? `${eventTotal}` : item.value,
    ];
    return { ...item, value: values[index] };
  });
  return { ...source, metrics };
});

let generation = 0;
const load = async () => {
  generation += 1;
  const version = generation;
  loading.value = true;
  failed.value = false;
  integration.value = null;
  health.value = null;
  events.value = [];
  try {
    const [capabilitiesResponse, healthResponse, eventsResponse] =
      await Promise.all([
        JrcContactCenterAPI.integrationCapabilities(accountId.value),
        JrcContactCenterAPI.operationalHealth(accountId.value),
        JrcContactCenterAPI.events(accountId.value),
      ]);
    if (version !== generation) return;
    integration.value = capabilitiesResponse.data;
    health.value = healthResponse.data;
    events.value = eventsResponse.data.items || [];
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) loading.value = false;
  }
};

const reprocess = async event => {
  if (
    reprocessing.value ||
    !event.signature_verified ||
    event.status !== 'failed'
  )
    return;
  const version = generation;
  reprocessing.value = true;
  try {
    await JrcContactCenterAPI.reprocessEvent(accountId.value, event.id);
    if (version === generation) await load();
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    reprocessing.value = false;
  }
};

const statusTone = status => {
  if (['processed', 'confirmed', 'ready', 'available'].includes(status))
    return 'emerald';
  if (['failed', 'rejected', 'unknown'].includes(status)) return 'ruby';
  if (['pending_contract', 'requested', 'pending'].includes(status))
    return 'amber';
  return 'blue';
};

watch(accountId, load, { immediate: true });
</script>

<template>
  <div>
    <VisualShowcasePage :screen="controlDeskScreen" />

    <section class="space-y-5 px-4 pb-6 sm:px-6">
      <div class="flex items-center justify-between gap-3">
        <div>
          <p class="text-sm font-semibold text-n-slate-12">
            {{ t('JRC_CONTACT_CENTER.CONTROL_DESK.CAPABILITIES') }}
          </p>
          <p class="mt-1 text-xs text-n-slate-10">
            {{
              integration?.provider || t('JRC_CONTACT_CENTER.COMMON.UNKNOWN')
            }}
          </p>
        </div>
        <button
          type="button"
          class="inline-flex items-center gap-2 rounded-xl border border-n-weak bg-n-solid-2 px-3 py-2 text-sm font-semibold text-n-slate-11 shadow-sm"
          @click="load"
        >
          <Icon icon="i-lucide-refresh-cw" class="size-4" />
          {{ t('JRC_CONTACT_CENTER.COMMON.REFRESH') }}
        </button>
      </div>

      <div
        v-if="failed"
        class="rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
      >
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </div>

      <div
        class="grid gap-5 xl:grid-cols-[minmax(0,1.35fr)_minmax(320px,.65fr)]"
      >
        <VisualSectionCard
          :title="$t('JRC_CONTACT_CENTER.VISUAL.EVENTOS_E_RECONCILIACAO')"
          :subtitle="
            loading
              ? t('JRC_CONTACT_CENTER.COMMON.LOADING')
              : $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1148')
          "
          icon="i-lucide-webhook"
          flush
        >
          <div v-if="events.length === 0" class="p-5 text-sm text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </div>
          <div v-else class="divide-y divide-n-weak">
            <div
              v-for="event in events"
              :key="event.id"
              class="flex flex-wrap items-center gap-3 px-4 py-4 sm:px-5"
            >
              <span
                class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11"
              >
                <Icon icon="i-lucide-webhook" class="size-5" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-semibold text-n-slate-12">
                  {{ event.event_type }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1149') }}{{ event.id
                  }}{{ $t('JRC_CONTACT_CENTER.VISUAL.ASSINATURA')
                  }}{{
                    event.signature_verified
                      ? $t('JRC_CONTACT_CENTER.VISUAL.VERIFIED')
                      : $t('JRC_CONTACT_CENTER.VISUAL.NOT_VERIFIED')
                  }}
                </p>
              </div>
              <VisualStatusBadge
                :label="event.status"
                :tone="statusTone(event.status)"
              />
              <button
                v-if="event.status === 'failed' && event.signature_verified"
                type="button"
                :disabled="reprocessing"
                class="rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2 text-xs font-semibold text-n-slate-11 shadow-sm disabled:opacity-50"
                @click="reprocess(event)"
              >
                {{ t('JRC_CONTACT_CENTER.CONTROL_DESK.REPROCESS') }}
              </button>
            </div>
          </div>
        </VisualSectionCard>

        <VisualSectionCard
          :title="$t('JRC_CONTACT_CENTER.VISUAL.MATRIZ_DE_CAPACIDADES')"
          :subtitle="
            $t(
              'JRC_CONTACT_CENTER.VISUAL.CONTRATO_EXTERNO_E_DISPONIBILIDADE_POR_RECURSO'
            )
          "
          icon="i-lucide-list-checks"
          flush
        >
          <div
            v-if="capabilityRows.length === 0"
            class="p-5 text-sm text-n-slate-10"
          >
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </div>
          <div v-else class="divide-y divide-n-weak">
            <div
              v-for="[capability, status] in capabilityRows"
              :key="capability"
              class="flex items-center justify-between gap-3 px-4 py-3.5"
            >
              <span class="text-sm font-medium text-n-slate-11">{{
                capability
              }}</span>
              <VisualStatusBadge :label="status" :tone="statusTone(status)" />
            </div>
          </div>
        </VisualSectionCard>
      </div>

      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article
          v-for="[status, count] in Object.entries(
            health?.events?.statuses || {}
          )"
          :key="`event-${status}`"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
        >
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-9"
          >
            {{ $t('JRC_CONTACT_CENTER.VISUAL.EVENTO') }}{{ status }}
          </p>
          <p class="mt-2 text-2xl font-bold text-n-slate-12">{{ count }}</p>
        </article>
        <article
          v-for="[status, count] in Object.entries(
            health?.commands?.statuses || {}
          )"
          :key="`command-${status}`"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
        >
          <p
            class="text-xs font-semibold uppercase tracking-wide text-n-slate-9"
          >
            {{ $t('JRC_CONTACT_CENTER.VISUAL.COMANDO') }}{{ status }}
          </p>
          <p class="mt-2 text-2xl font-bold text-n-slate-12">{{ count }}</p>
        </article>
      </div>
    </section>
  </div>
</template>
