<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualShowcasePage from '../components/visual/VisualShowcasePage.vue';
import VisualSectionCard from '../components/visual/VisualSectionCard.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import { contactCenterScreen } from '../demo/contactCenterVisualCatalog';
import AgentStatePanel from './AgentStatePanel.vue';
import CallWorkspace from './CallWorkspace.vue';

const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const loading = ref(true);
const failed = ref(false);
const context = ref(null);
const calls = ref([]);
const callbacks = ref([]);
const selectedCallId = ref(null);
let generation = 0;

const accountId = computed(() => route.params.accountId);
const selectedCallbackId = computed(() => String(route.query.callbackId || ''));

const cockpitScreen = computed(() => {
  const source = contactCenterScreen('cockpit', t);
  const counts = context.value?.counts || {};
  const metrics = source.metrics.map((item, index) => {
    const values = [
      counts.active_calls ?? item.value,
      counts.pending_callbacks ?? item.value,
      item.value,
      counts.open_cases ?? item.value,
    ];
    return { ...item, value: values[index] };
  });
  return { ...source, metrics };
});

const activeCalls = computed(() =>
  calls.value.filter(
    call => !['ended', 'failed', 'abandoned'].includes(call.status)
  )
);

const refreshCallbacks = async () => {
  const version = generation;
  try {
    const [response, contextResponse] = await Promise.all([
      JrcContactCenterAPI.callbacks(accountId.value),
      JrcContactCenterAPI.context(accountId.value),
    ]);
    if (version !== generation) return;
    context.value = contextResponse.data;
    callbacks.value = (response.data.items || []).filter(item =>
      ['scheduled', 'in_progress', 'failed'].includes(item.state)
    );
  } catch {
    if (version === generation) failed.value = true;
  }
};

const formatDate = value =>
  value
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : '-';

const openCall = call => {
  selectedCallId.value = call.id;
  router.replace({
    query: { ...route.query, callId: String(call.id) },
  });
};

watch(
  accountId,
  async id => {
    generation += 1;
    const version = generation;
    loading.value = true;
    failed.value = false;
    context.value = null;
    calls.value = [];
    callbacks.value = [];
    selectedCallId.value = null;
    try {
      const [contextResponse, callsResponse, callbacksResponse] =
        await Promise.all([
          JrcContactCenterAPI.context(id),
          JrcContactCenterAPI.calls(id, { limit: 20 }),
          JrcContactCenterAPI.callbacks(id),
        ]);
      if (version !== generation) return;
      context.value = contextResponse.data;
      calls.value = callsResponse.data.items || [];
      callbacks.value = (callbacksResponse.data.items || []).filter(item =>
        ['scheduled', 'in_progress', 'failed'].includes(item.state)
      );
      const queryCallId = Number(route.query.callId);
      if (Number.isInteger(queryCallId) && queryCallId > 0) {
        selectedCallId.value = queryCallId;
      }
    } catch {
      if (version === generation) failed.value = true;
    } finally {
      if (version === generation) loading.value = false;
    }
  },
  { immediate: true }
);
</script>

<template>
  <div>
    <VisualShowcasePage :screen="cockpitScreen" />

    <section class="space-y-5 px-4 pb-6 sm:px-6">
      <AgentStatePanel
        :account-id="accountId"
        :can-operate="context?.capabilities?.operate === true"
      />

      <div
        v-if="failed"
        class="rounded-2xl border border-n-amber-6 bg-n-amber-2 p-4 text-sm text-n-amber-11"
      >
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </div>

      <CallWorkspace
        v-if="selectedCallId"
        :key="`${accountId}-${selectedCallId}`"
        :account-id="accountId"
        :call-id="selectedCallId"
        :context="context"
        @created="refreshCallbacks"
      />

      <div
        class="grid gap-5 2xl:grid-cols-[minmax(0,1.3fr)_minmax(320px,.7fr)]"
      >
        <VisualSectionCard
          :title="t('JRC_CONTACT_CENTER.COCKPIT.RECENT_CALLS')"
          :subtitle="loading ? t('JRC_CONTACT_CENTER.COMMON.LOADING') : ''"
          icon="i-lucide-phone-call"
          flush
        >
          <div v-if="calls.length === 0" class="p-5 text-sm text-n-slate-10">
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </div>
          <div v-else class="divide-y divide-n-weak">
            <button
              v-for="call in calls"
              :key="call.id"
              type="button"
              class="flex w-full items-center gap-3 px-4 py-4 text-left transition hover:bg-n-alpha-1 sm:px-5"
              @click="openCall(call)"
            >
              <span
                class="grid size-11 shrink-0 place-content-center rounded-2xl bg-n-blue-2 text-n-blue-11"
              >
                <Icon
                  :icon="
                    call.direction === 'outbound'
                      ? 'i-lucide-phone-outgoing'
                      : 'i-lucide-phone-incoming'
                  "
                  class="size-5"
                />
              </span>
              <span class="min-w-0 flex-1">
                <span
                  class="block break-words text-sm font-semibold text-n-slate-12"
                >
                  {{ call.ani || call.dnis || `#${call.id}` }}
                </span>
                <span class="mt-1 block break-words text-xs text-n-slate-10">
                  {{ call.direction
                  }}{{ $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1145')
                  }}{{ formatDate(call.started_at) }}
                </span>
              </span>
              <VisualStatusBadge
                :label="call.status"
                :tone="
                  activeCalls.some(item => item.id === call.id)
                    ? 'emerald'
                    : 'slate'
                "
              />
            </button>
          </div>
        </VisualSectionCard>

        <VisualSectionCard
          :title="t('JRC_CONTACT_CENTER.COCKPIT.CALLBACKS')"
          icon="i-lucide-calendar-clock"
          flush
        >
          <div
            v-if="callbacks.length === 0"
            class="p-5 text-sm text-n-slate-10"
          >
            {{ t('JRC_CONTACT_CENTER.COMMON.EMPTY') }}
          </div>
          <div v-else class="divide-y divide-n-weak">
            <div
              v-for="callback in callbacks"
              :key="callback.id"
              class="flex items-center gap-3 px-4 py-4"
              :class="
                String(callback.id) === selectedCallbackId ? 'bg-n-amber-2' : ''
              "
            >
              <span
                class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-iris-2 text-n-iris-11"
              >
                <Icon icon="i-lucide-calendar-clock" class="size-4" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="break-words text-sm font-semibold text-n-slate-12">
                  {{ callback.target_phone || `#${callback.contact_id}` }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ formatDate(callback.scheduled_at) }}
                </p>
              </div>
              <VisualStatusBadge :label="callback.state" tone="violet" />
            </div>
          </div>
        </VisualSectionCard>
      </div>
    </section>
  </div>
</template>
