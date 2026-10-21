<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import VisualSectionCard from '../components/visual/VisualSectionCard.vue';
import VisualStatusBadge from '../components/visual/VisualStatusBadge.vue';
import { callStateLabels } from '../../inbox/inboxPresentation';

const props = defineProps({
  accountId: { type: [String, Number], required: true },
  callId: { type: [String, Number], required: true },
  context: { type: Object, default: () => ({}) },
  compact: { type: Boolean, default: false },
  section: { type: String, default: 'all' },
});
const emit = defineEmits(['created', 'loaded']);
const { t, locale } = useI18n();
const callLabels = computed(() => callStateLabels(t));
const journeyTime = value =>
  props.compact && value
    ? new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : value;
const actionLabels = computed(() => ({
  transfer_blind: t('JRC_CONTACT_CENTER.CALL.transfer_blind'),
  transfer_attended: t('JRC_CONTACT_CENTER.CALL.transfer_attended'),
}));
const call = ref(null);
const customer = ref(null);
const agent = ref(null);
const busy = ref(false);
const failed = ref(false);
const saved = ref(false);
const summary = ref('');
const category = ref('');
const scheduledAt = ref('');
const destination = ref('');
let generation = 0;
const canOperate = computed(
  () => props.context?.capabilities?.operate === true
);
const sipAvailable = computed(
  () =>
    canOperate.value &&
    props.context?.provider?.capabilities?.sip_webrtc === 'available'
);
const phone = computed(() =>
  call.value?.direction === 'outbound' ? call.value?.dnis : call.value?.ani
);
const callTone = computed(() => {
  const tones = {
    active: 'emerald',
    answered: 'emerald',
    connected: 'emerald',
    ringing: 'amber',
    queued: 'blue',
    ended: 'slate',
    abandoned: 'ruby',
    failed: 'ruby',
  };
  return tones[call.value?.status] || 'blue';
});
const customerName = computed(
  () => customer.value?.contacts?.[0]?.name || phone.value || '-'
);
const customerCompany = computed(
  () =>
    customer.value?.contacts?.[0]?.company?.name ||
    t('JRC_CONTACT_CENTER.VISUAL.UNCONFIRMED_COMPANY')
);
const journeyEvents = computed(() => [
  ...(call.value?.journey?.ivr || []).map(event => ({
    id: `ivr-${event.id}`,
    icon: 'i-lucide-git-branch',
    title: event.menu_key || t('JRC_CONTACT_CENTER.VISUAL.IVR'),
    detail: event.option_key || '-',
    time: journeyTime(event.occurred_at),
  })),
  ...(call.value?.journey?.legs || []).map(leg => ({
    id: `leg-${leg.id}`,
    icon: 'i-lucide-phone-call',
    title: props.compact
      ? t('JRC_CONTACT_CENTER.INBOX_360.AGENT_LEG')
      : `Perna ${leg.id}`,
    detail: props.compact
      ? callLabels.value[leg.status]
      : `${leg.status} · Fila ${leg.queue_id || '-'}`,
    time: journeyTime(leg.started_at || leg.created_at),
  })),
]);

const load = async () => {
  generation += 1;
  const version = generation;
  call.value = null;
  customer.value = null;
  agent.value = null;
  failed.value = false;
  saved.value = false;
  summary.value = '';
  category.value = '';
  scheduledAt.value = '';
  destination.value = '';
  busy.value = true;
  emit('loaded', null);
  try {
    const [callResponse, agentResponse] = await Promise.all([
      JrcContactCenterAPI.call(props.accountId, props.callId),
      JrcContactCenterAPI.agentState(props.accountId),
    ]);
    if (version !== generation) return;
    call.value = callResponse.data.item;
    agent.value = agentResponse.data.item;
    if (phone.value) {
      const response = await JrcContactCenterAPI.customerContext(
        props.accountId,
        phone.value
      );
      if (version === generation) customer.value = response.data;
    }
    if (version === generation)
      emit('loaded', {
        call: call.value,
        customer: customer.value,
        agent: agent.value,
      });
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) busy.value = false;
  }
};

const createRecord = async kind => {
  if (!canOperate.value || busy.value || !call.value || !agent.value) return;
  const version = generation;
  busy.value = true;
  failed.value = false;
  saved.value = false;
  const attributes = {
    call_session_id: call.value.id,
    contact_id: call.value.contact_id || undefined,
    owner_account_user_id: agent.value.account_user_id,
  };
  try {
    if (kind === 'case') {
      await JrcContactCenterAPI.createCase(props.accountId, {
        ...attributes,
        channel: 'phone',
        category: category.value.trim(),
        summary: summary.value.trim(),
      });
    } else {
      await JrcContactCenterAPI.createCallback(props.accountId, {
        ...attributes,
        target_phone: phone.value,
        scheduled_at: new Date(scheduledAt.value).toISOString(),
        idempotency_key: crypto.randomUUID(),
      });
    }
    if (version === generation) {
      saved.value = true;
      if (kind === 'case') {
        summary.value = '';
        category.value = '';
      } else {
        scheduledAt.value = '';
      }
      emit('created');
    }
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) busy.value = false;
  }
};

const command = async action => {
  const capability = {
    transfer_blind: 'transfer_blind',
    transfer_attended: 'transfer_attended',
  }[action];
  if (
    !canOperate.value ||
    busy.value ||
    props.context?.provider?.capabilities?.[capability] !== 'available'
  )
    return;
  const version = generation;
  busy.value = true;
  failed.value = false;
  try {
    await JrcContactCenterAPI.createCommand(props.accountId, {
      action,
      command_id: crypto.randomUUID(),
      call_session_id: call.value.id,
      expected_state_version: call.value.lock_version,
      parameters: { destination: destination.value.trim() },
    });
    if (version === generation) await load();
  } catch {
    if (version === generation) failed.value = true;
  } finally {
    if (version === generation) busy.value = false;
  }
};

watch(() => [props.accountId, props.callId], load, { immediate: true });
onBeforeUnmount(() => {
  generation += 1;
});
defineExpose({
  setCategory: value => {
    category.value = value;
  },
});
</script>

<template>
  <section
    class="overflow-hidden rounded-[28px] border border-n-weak bg-n-solid-2 shadow-[0_18px_48px_rgba(15,46,82,.12)]"
  >
    <header
      v-if="!compact"
      class="relative overflow-hidden bg-gradient-to-r from-[#102e55] via-[#174f7f] to-[#087cc9] p-5 text-white sm:p-6"
    >
      <span
        aria-hidden="true"
        class="pointer-events-none absolute -right-16 -top-24 size-72 rounded-full bg-white/10 blur-3xl"
      />
      <div class="relative flex flex-wrap items-center justify-between gap-4">
        <div class="flex min-w-0 items-center gap-4">
          <span
            class="grid size-12 shrink-0 place-content-center rounded-2xl bg-white/15 ring-1 ring-white/20"
          >
            <Icon icon="i-lucide-phone-call" class="size-6" />
          </span>
          <div class="min-w-0">
            <p
              class="text-xs font-semibold uppercase tracking-[0.18em] text-white/70"
            >
              {{ $t('JRC_CONTACT_CENTER.VISUAL.ATENDIMENTO_EM_ANDAMENTO') }}
            </p>
            <div class="mt-1 flex flex-wrap items-center gap-3">
              <h3 class="break-words text-xl font-bold text-white sm:text-2xl">
                {{ phone || '-' }}
              </h3>
              <VisualStatusBadge
                v-if="call"
                :label="call.status"
                :tone="callTone"
                dot
                class="border-white/25 bg-white/90"
              />
            </div>
            <p class="mt-1 text-sm text-white/75">
              {{ customerName }}{{ $t('JRC_CONTACT_CENTER.VISUAL.TEXT_1145')
              }}{{ customerCompany }}
            </p>
          </div>
        </div>
        <RouterLink
          v-if="sipAvailable"
          :to="{ name: 'ramal_index', params: { accountId } }"
          class="inline-flex items-center gap-2 rounded-xl border border-white/20 bg-white/10 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-white/15"
        >
          <Icon icon="i-lucide-headset" class="size-4" />
          {{ t('JRC_CONTACT_CENTER.CALL.WEBPHONE') }}
        </RouterLink>
      </div>
    </header>

    <div class="p-4 sm:p-5">
      <div
        v-if="failed"
        role="alert"
        class="mb-4 rounded-2xl border border-n-ruby-5 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
      >
        {{ t('JRC_CONTACT_CENTER.COMMON.ERROR') }}
      </div>
      <div
        v-if="saved"
        role="status"
        class="mb-4 rounded-2xl border border-n-teal-5 bg-n-teal-2 p-4 text-sm text-n-teal-11"
      >
        {{ t('JRC_CONTACT_CENTER.CALL.SAVED') }}
      </div>

      <div
        v-if="busy && !call"
        class="grid animate-pulse gap-4 2xl:grid-cols-3"
      >
        <div
          v-for="index in 3"
          :key="index"
          class="h-72 rounded-2xl bg-n-alpha-2"
        />
      </div>

      <div
        v-else-if="call"
        class="grid gap-4"
        :class="compact ? '' : '2xl:grid-cols-3'"
      >
        <VisualSectionCard
          v-if="!compact || section === 'journey'"
          :title="$t('JRC_CONTACT_CENTER.VISUAL.JORNADA_DA_CHAMADA')"
          :subtitle="
            compact
              ? ''
              : $t('JRC_CONTACT_CENTER.VISUAL.URA_FILA_PERNAS_E_TRANSFERENCIAS')
          "
          icon="i-lucide-workflow"
        >
          <div v-if="journeyEvents.length" class="space-y-3">
            <div
              v-for="item in journeyEvents"
              :key="item.id"
              class="flex flex-wrap gap-3 rounded-xl border border-n-weak bg-n-alpha-1 p-3"
            >
              <span
                class="grid size-9 shrink-0 place-content-center rounded-xl bg-n-blue-2 text-n-blue-11"
              >
                <Icon :icon="item.icon" class="size-4" />
              </span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ item.title }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ item.detail }}
                </p>
              </div>
              <span class="w-full break-all text-[11px] text-n-slate-9">
                {{ item.time }}
              </span>
            </div>
          </div>
          <div
            v-else
            class="rounded-xl border border-dashed border-n-weak p-5 text-center text-sm text-n-slate-10"
          >
            {{
              $t(
                'JRC_CONTACT_CENTER.VISUAL.JORNADA_AGUARDANDO_EVENTOS_CONFIRMADOS'
              )
            }}
          </div>
          <p
            v-if="!sipAvailable && !compact"
            class="mt-4 flex gap-2 rounded-xl border border-n-amber-5 bg-n-amber-2 p-3 text-xs leading-5 text-n-amber-11"
          >
            <Icon icon="i-lucide-clock-3" class="mt-0.5 size-4 shrink-0" />
            {{ t('JRC_CONTACT_CENTER.CALL.PHONE_PENDING') }}
          </p>
        </VisualSectionCard>

        <VisualSectionCard
          v-if="!compact"
          :title="$t('JRC_CONTACT_CENTER.VISUAL.CLIENTE_E_OTICA_360')"
          :subtitle="
            compact
              ? ''
              : $t(
                  'JRC_CONTACT_CENTER.VISUAL.IDENTIFICACAO_EMPRESA_E_CONTEXTO_AUTORIZADO'
                )
          "
          icon="i-lucide-orbit"
        >
          <p
            v-if="customer?.ambiguous"
            class="mb-3 rounded-xl border border-n-amber-5 bg-n-amber-2 p-3 text-sm text-n-amber-11"
          >
            {{ t('JRC_CONTACT_CENTER.CALL.AMBIGUOUS') }}
          </p>
          <div
            v-for="contact in customer?.contacts || []"
            :key="contact.id"
            class="mb-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-4 last:mb-0"
          >
            <div class="flex items-start gap-3">
              <span
                class="grid size-11 shrink-0 place-content-center rounded-full bg-n-iris-2 text-sm font-bold text-n-iris-11"
              >
                {{
                  String(contact.name || 'C')
                    .slice(0, 1)
                    .toUpperCase()
                }}
              </span>
              <div class="min-w-0 flex-1">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ contact.name }}
                </p>
                <p class="mt-1 text-xs text-n-slate-10">
                  {{ contact.company?.name || '-' }}
                </p>
                <div class="mt-3 flex flex-wrap gap-2">
                  <VisualStatusBadge
                    :label="$t('JRC_CONTACT_CENTER.VISUAL.CADASTRO_MESTRE')"
                    tone="blue"
                  />
                  <VisualStatusBadge
                    :label="$t('JRC_CONTACT_CENTER.VISUAL.CRM_360')"
                    tone="violet"
                  />
                </div>
              </div>
            </div>
          </div>
          <div
            v-if="(customer?.contacts || []).length === 0"
            class="rounded-xl border border-dashed border-n-weak p-5 text-center text-sm text-n-slate-10"
          >
            {{ $t('JRC_CONTACT_CENTER.VISUAL.CLIENTE_AINDA_NAO_CONFIRMADO') }}
          </div>
          <div
            class="mt-4 rounded-xl border border-n-weak bg-n-alpha-1 p-3 text-xs leading-5 text-n-amber-11"
          >
            {{ t('JRC_CONTACT_CENTER.CALL.ERP_PENDING') }}
          </div>
        </VisualSectionCard>

        <div class="space-y-5">
          <VisualSectionCard
            v-if="canOperate && (!compact || section === 'transfer')"
            :title="$t('JRC_CONTACT_CENTER.VISUAL.TRANSFERENCIA_CONTEXTUAL')"
            :subtitle="
              compact
                ? ''
                : $t(
                    'JRC_CONTACT_CENTER.VISUAL.DESTINO_E_COMANDO_CONFIRMADOS_PELO_PROVIDER'
                  )
            "
            icon="i-lucide-arrow-left-right"
          >
            <div class="space-y-3">
              <input
                v-model="destination"
                :aria-label="t('JRC_CONTACT_CENTER.COMMON.TARGET')"
                :placeholder="t('JRC_CONTACT_CENTER.COMMON.TARGET')"
                class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
              />
              <button
                v-for="action in ['transfer_blind', 'transfer_attended']"
                :key="action"
                type="button"
                :disabled="
                  busy ||
                  !destination.trim() ||
                  ['ended', 'failed'].includes(call.status) ||
                  context.provider?.capabilities?.[action] !== 'available'
                "
                class="flex w-full items-center justify-center gap-2 rounded-xl border border-n-weak bg-n-solid-2 px-4 py-2.5 text-sm font-semibold text-n-slate-11 shadow-sm transition hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-50"
                @click="command(action)"
              >
                <Icon icon="i-lucide-phone-forwarded" class="size-4" />
                {{ actionLabels[action] }}
              </button>
            </div>
          </VisualSectionCard>

          <VisualSectionCard
            v-if="canOperate && (!compact || section === 'case')"
            :title="$t('JRC_CONTACT_CENTER.VISUAL.REGISTRAR_OCORRENCIA')"
            :subtitle="
              compact
                ? ''
                : $t(
                    'JRC_CONTACT_CENTER.VISUAL.OCORRENCIA_NATIVA_SEM_SERVICE_DESK'
                  )
            "
            icon="i-lucide-clipboard-plus"
          >
            <div class="space-y-3">
              <input
                v-model="category"
                :aria-label="t('JRC_CONTACT_CENTER.CALL.CATEGORY')"
                :placeholder="t('JRC_CONTACT_CENTER.CALL.CATEGORY')"
                class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
              />
              <textarea
                v-model="summary"
                rows="3"
                :aria-label="t('JRC_CONTACT_CENTER.OCCURRENCES.SUMMARY')"
                :placeholder="t('JRC_CONTACT_CENTER.OCCURRENCES.SUMMARY')"
                class="w-full resize-none rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
              />
              <button
                type="button"
                :disabled="busy || !category.trim() || !summary.trim()"
                class="inline-flex w-full items-center justify-center gap-2 rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                @click="createRecord('case')"
              >
                <Icon icon="i-lucide-save" class="size-4" />
                {{ t('JRC_CONTACT_CENTER.CALL.CREATE_CASE') }}
              </button>
            </div>
          </VisualSectionCard>

          <VisualSectionCard
            v-if="canOperate && (!compact || section === 'callback')"
            :title="$t('JRC_CONTACT_CENTER.VISUAL.CALLBACK')"
            :subtitle="
              compact
                ? ''
                : $t('JRC_CONTACT_CENTER.VISUAL.AGENDA_INTEGRADA_E_IDEMPOTENTE')
            "
            icon="i-lucide-calendar-clock"
          >
            <div class="space-y-3">
              <input
                v-model="scheduledAt"
                type="datetime-local"
                :aria-label="t('JRC_CONTACT_CENTER.COMMON.SCHEDULED_AT')"
                class="w-full rounded-xl border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm outline-none transition focus:border-n-blue-7 focus:ring-2 focus:ring-n-blue-3"
              />
              <button
                type="button"
                :disabled="busy || !scheduledAt || !phone"
                class="inline-flex w-full items-center justify-center gap-2 rounded-xl border border-n-blue-6 bg-n-blue-2 px-4 py-2.5 text-sm font-semibold text-n-blue-11 shadow-sm transition hover:bg-n-blue-3 disabled:cursor-not-allowed disabled:opacity-50"
                @click="createRecord('callback')"
              >
                <Icon icon="i-lucide-calendar-plus" class="size-4" />
                {{ t('JRC_CONTACT_CENTER.CALL.CREATE_CALLBACK') }}
              </button>
            </div>
          </VisualSectionCard>
        </div>
      </div>
    </div>
  </section>
</template>
