<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CallHistoryAPI from 'dashboard/api/callHistory';
import CallQualityAnalysesAPI from 'dashboard/api/callQualityAnalyses';

const { t } = useI18n();
const recordings = ref({});
const recordingBusy = ref({});
const recordingErrors = ref({});
const recordingControllers = new Map();
let recordingGeneration = 0;
let disposed = false;
const page = ref(1);
const provider = ref('');
const sync = ref({});

const clearRecordings = () => {
  recordingGeneration += 1;
  recordingControllers.forEach(controller => controller.abort());
  recordingControllers.clear();
  Object.values(recordings.value).forEach(url => URL.revokeObjectURL(url));
  recordings.value = {};
  recordingBusy.value = {};
};

const loadRecording = async call => {
  if (recordingBusy.value[call.id] || call.recording_state !== 'requestable')
    return;
  clearRecordings();
  const generation = recordingGeneration;
  const controller = new AbortController();
  recordingControllers.set(call.id, controller);
  delete recordingErrors.value[call.id];
  recordingBusy.value[call.id] = true;
  try {
    const { data } = await CallHistoryAPI.recording(call.id, {
      signal: controller.signal,
    });
    if (disposed || generation !== recordingGeneration) return;
    recordings.value[call.id] = URL.createObjectURL(data);
  } catch (error) {
    if (
      disposed ||
      generation !== recordingGeneration ||
      error?.code === 'ERR_CANCELED'
    )
      return;
    recordingErrors.value[call.id] =
      {
        403: t('SOFTPHONE.PABX.RECORDING_FORBIDDEN'),
        404: t('SOFTPHONE.PABX.RECORDING_UNAVAILABLE'),
        410: t('SOFTPHONE.PABX.RECORDING_EXPIRED'),
      }[error?.response?.status] || t('SOFTPHONE.PABX.RECORDING_ERROR');
  } finally {
    if (!disposed && generation === recordingGeneration)
      recordingBusy.value[call.id] = false;
    if (recordingControllers.get(call.id) === controller)
      recordingControllers.delete(call.id);
  }
};
onUnmounted(() => {
  disposed = true;
  clearRecordings();
});

const TEXT = Object.freeze({
  kicker: 'TELEFONIA',
  title: 'Historico de chamadas',
  refresh: 'Atualizar historico',
  allDirections: 'Todas as direcoes',
  inbound: 'Recebidas',
  outbound: 'Realizadas',
  local: 'Internas',
  allStatuses: 'Todos os status',
  answered: 'Atendidas',
  unanswered: 'Nao atendidas',
  busy: 'Ocupado',
  cancelled: 'Canceladas',
  failed: 'Falhas',
  analyzeQuality: 'Analisar qualidade',
  analyzingQuality: 'Analisando...',
  analyzedQuality: 'Analisada',
  analysisError: 'Erro na analise',
  viewAnalysis: 'Ver analise',
  hideAnalysis: 'Ocultar analise',
  consultTitle: 'Consulte quando precisar',
  consultDescription:
    'O historico permanece no PABX e so e buscado ao abrir esta consulta.',
  empty: 'Nenhuma chamada encontrada no periodo.',
  totalCalls: 'Total de chamadas',
  summaryAnswered: 'Atendidas',
  summaryUnanswered: 'Não atendidas',
  analysisSummary: 'Resumo',
});

const DIRECTION_OPTIONS = [
  ['', TEXT.allDirections],
  ['inbound', TEXT.inbound],
  ['outbound', TEXT.outbound],
  ['local', TEXT.local],
  ['api', 'API'],
];
const STATUS_OPTIONS = [
  ['', TEXT.allStatuses],
  ['answered', TEXT.answered],
  ['unanswered', TEXT.unanswered],
  ['missed', 'Perdidas (recebidas não atendidas)'],
  ['busy', TEXT.busy],
  ['cancelled', TEXT.cancelled],
  ['failed', TEXT.failed],
  ['congestion', 'Congestionada'],
];

const loading = ref(false);
const loaded = ref(false);
const errorMessage = ref('');
const calls = ref([]);
const total = ref(0);
const summary = ref({ total: 0, answered: 0, unanswered: 0 });
const extension = ref('');
const fetchedAt = ref('');
const period = ref(7);
const direction = ref('');
const status = ref('');
const customStart = ref('');
const customEnd = ref('');
const analysisStates = ref({});
const selectedAnalysisKey = ref('');
const SAO_PAULO_TIME_ZONE = 'America/Sao_Paulo';
const AUTO_REFRESH_INTERVAL_MS = 60000;
let autoRefreshTimer = null;

const today = () => {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: SAO_PAULO_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
};
const isoDaysAgo = days => {
  const value = new Date(`${today()}T12:00:00Z`);
  value.setUTCDate(value.getUTCDate() - days);
  return value.toISOString().slice(0, 10);
};

const queryDates = computed(() => {
  if (period.value === 'custom') {
    return { start_date: customStart.value, end_date: customEnd.value };
  }
  return {
    start_date: isoDaysAgo(Number(period.value) - 1),
    end_date: today(),
  };
});
const historySummary = computed(
  () => `Ramal ${extension.value} · ${total.value} registro(s)`
);
const actionLabel = computed(() => {
  if (loading.value) return 'Buscando histórico...';
  return loaded.value ? 'Aplicar filtros' : 'Carregar historico';
});
const callTimestamp = call =>
  Date.parse(call.started_at || call.answered_at || call.ended_at || '') || 0;
const sortedCalls = computed(() =>
  [...calls.value].sort(
    (first, second) => callTimestamp(second) - callTimestamp(first)
  )
);

const fetchHistory = async () => {
  if (loading.value) return;
  if (period.value === 'custom' && (!customStart.value || !customEnd.value)) {
    errorMessage.value = 'Informe as datas inicial e final.';
    return;
  }

  loading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await CallHistoryAPI.get({
      ...queryDates.value,
      direction: direction.value || undefined,
      status: status.value || undefined,
      per_page: 100,
      page: page.value,
      time_zone: SAO_PAULO_TIME_ZONE,
    });
    if (disposed) return;
    clearRecordings();
    recordingErrors.value = {};
    calls.value = data.calls;
    provider.value = data.provider || '';
    sync.value = data.sync || {};
    total.value = data.count;
    summary.value =
      data.summary ||
      data.calls.reduce(
        (result, call) => ({
          total: result.total + 1,
          answered: result.answered + Number(call.status === 'answered'),
          unanswered: result.unanswered + Number(call.status === 'unanswered'),
        }),
        { total: 0, answered: 0, unanswered: 0 }
      );
    extension.value = data.extension;
    fetchedAt.value = data.fetched_at;
    loaded.value = true;
  } catch (error) {
    if (disposed) return;
    clearRecordings();
    recordingErrors.value = {};
    calls.value = [];
    total.value = 0;
    summary.value = { total: 0, answered: 0, unanswered: 0 };
    provider.value = '';
    sync.value = {};
    errorMessage.value =
      error?.response?.data?.message ||
      'Não foi possível consultar o PABX. Tente novamente.';
    loaded.value = true;
  } finally {
    loading.value = false;
  }
};

const setPeriod = value => {
  page.value = 1;
  period.value = value;
};
const applyFilters = () => {
  page.value = 1;
  fetchHistory();
};

const canAutoRefresh = () => {
  if (typeof document !== 'undefined' && document.hidden) return false;
  if (period.value === 'custom' && (!customStart.value || !customEnd.value)) {
    return false;
  }
  return !loading.value;
};

const scheduleAutoRefresh = () => {
  if (autoRefreshTimer) window.clearInterval(autoRefreshTimer);
  autoRefreshTimer = window.setInterval(() => {
    if (canAutoRefresh()) fetchHistory();
  }, AUTO_REFRESH_INTERVAL_MS);
};

const handleVisibilityChange = () => {
  if (!document.hidden && loaded.value && canAutoRefresh()) {
    fetchHistory();
  }
};

const timestampInfo = value => {
  if (!value) return null;
  const raw = String(value);
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return null;

  return {
    date: parsed,
    timeZone: SAO_PAULO_TIME_ZONE,
  };
};

const formatDate = value => {
  const info = timestampInfo(value);
  if (!info) return 'Horario nao informado';
  return new Intl.DateTimeFormat('pt-BR', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: info.timeZone,
  }).format(info.date);
};
const updatedText = computed(() =>
  fetchedAt.value ? `Atualizado em ${formatDate(fetchedAt.value)}` : ''
);

const formatDuration = seconds => {
  if (seconds === null || seconds === undefined) return '—';
  const value = Number(seconds || 0);
  const minutes = Math.floor(value / 60);
  const remainder = value % 60;
  return `${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`;
};

const directionMeta = value =>
  ({
    outbound: { label: 'Realizada', icon: 'i-lucide-phone-outgoing' },
    inbound: { label: 'Recebida', icon: 'i-lucide-phone-incoming' },
    local: { label: 'Interna', icon: 'i-lucide-phone-forwarded' },
    api: { label: 'API', icon: 'i-lucide-phone' },
  })[value] || { label: 'Chamada', icon: 'i-lucide-phone' };

const statusLabel = value =>
  ({
    answered: 'Atendida',
    unanswered: 'Nao atendida',
    busy: 'Ocupado',
    cancelled: 'Cancelada',
    failed: 'Falha',
    congestion: 'Congestionada',
  })[value] || value;

const statusClass = value =>
  ({
    answered: 'border-n-teal-7 bg-n-teal-3 text-n-teal-11',
    unanswered: 'border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11',
    busy: 'border-n-amber-7 bg-n-amber-3 text-n-amber-11',
    cancelled: 'border-n-slate-7 bg-n-slate-3 text-n-slate-11',
    failed: 'border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11',
  })[value] || 'border-n-weak bg-n-alpha-2 text-n-slate-11';

const directionClass = value =>
  ({
    outbound: 'bg-n-blue-3 text-n-blue-11',
    inbound: 'bg-n-teal-3 text-n-teal-11',
    local: 'bg-n-violet-3 text-n-violet-11',
  })[value] || 'bg-n-alpha-3 text-n-slate-11';

const relatedName = call => {
  if (call.direction === 'outbound') return call.callee?.name;
  return call.caller?.name;
};

const callNumber = call => call.external_number || 'Numero nao informado';

const callTiming = call =>
  `${formatDate(call.started_at)} · Conversa ${formatDuration(
    call.talk_duration_seconds
  )} · Total ${formatDuration(call.total_duration_seconds)}`;
const callKey = call => call.unique_id || call.id;

const analysisEntry = call => analysisStates.value[callKey(call)] || {};

const callAnalysis = call =>
  analysisEntry(call).analysis || call.quality_analysis || null;

const analysisErrorFor = call => analysisEntry(call).error || '';

const isAnalyzing = call => analysisEntry(call).status === 'analyzing';

const isAnalysisOpen = call => selectedAnalysisKey.value === callKey(call);

const qualityButtonLabel = call => {
  if (isAnalyzing(call)) return TEXT.analyzingQuality;
  if (analysisErrorFor(call)) return TEXT.analysisError;
  if (callAnalysis(call)) return TEXT.analyzedQuality;
  return TEXT.analyzeQuality;
};

const updateAnalysisState = (key, value) => {
  analysisStates.value = {
    ...analysisStates.value,
    [key]: {
      ...(analysisStates.value[key] || {}),
      ...value,
    },
  };
};

const analysisRequestPayload = call => ({
  id: call.id,
  unique_id: call.unique_id,
  started_at: call.started_at,
  start_date: queryDates.value.start_date,
  end_date: queryDates.value.end_date,
});

const analyzeCall = async call => {
  const key = callKey(call);
  if (!key || isAnalyzing(call) || callAnalysis(call)) return;

  updateAnalysisState(key, { status: 'analyzing', error: '' });
  try {
    const { data } = await CallQualityAnalysesAPI.analyze(
      analysisRequestPayload(call)
    );
    updateAnalysisState(key, {
      status: 'analyzed',
      analysis: data.analysis,
      error: '',
    });
    selectedAnalysisKey.value = key;
  } catch (error) {
    updateAnalysisState(key, {
      status: 'error',
      error:
        error?.response?.data?.message ||
        'Nao foi possivel analisar esta gravacao.',
    });
  }
};

const toggleAnalysis = call => {
  const key = callKey(call);
  selectedAnalysisKey.value = isAnalysisOpen(call) ? '' : key;
};

const formatValue = value => {
  if (value === null || value === undefined || value === '') {
    return 'Nao informado';
  }
  if (typeof value === 'boolean') return value ? 'Sim' : 'Nao';
  return String(value).replaceAll('_', ' ');
};

const analysisMetrics = analysis => [
  ['Nota final', analysis?.nota_final],
  ['Classificacao', analysis?.classificacao_ligacao],
  ['Sentimento cliente', analysis?.sentimento_cliente],
  ['Temperatura', analysis?.temperatura_conversa],
  ['Risco de churn', analysis?.risco_churn],
  ['Risco de reclamacao', analysis?.risco_reclamacao],
  ['Status', analysis?.status],
];

onMounted(() => {
  fetchHistory();
  scheduleAutoRefresh();
  document.addEventListener('visibilitychange', handleVisibilityChange);
});

onUnmounted(() => {
  if (autoRefreshTimer) window.clearInterval(autoRefreshTimer);
  document.removeEventListener('visibilitychange', handleVisibilityChange);
});
</script>

<template>
  <aside
    class="flex min-h-[560px] flex-col rounded-3xl border border-n-weak bg-n-solid-2 p-5 shadow-sm lg:p-6"
  >
    <header class="mb-5 flex items-start justify-between gap-3">
      <div>
        <p class="text-xs font-bold tracking-[0.14em] text-n-teal-11">
          {{ TEXT.kicker }}
        </p>
        <h2 class="mt-2 text-xl font-semibold text-n-slate-12">
          {{ TEXT.title }}
        </h2>
        <p v-if="extension" class="mt-1 text-xs text-n-slate-10">
          {{ historySummary }}
        </p>
      </div>
      <button
        v-if="loaded"
        type="button"
        class="flex size-10 items-center justify-center rounded-xl border border-n-weak text-n-slate-11 hover:border-n-brand hover:text-n-brand disabled:opacity-50"
        :disabled="loading"
        :title="TEXT.refresh"
        @click="fetchHistory"
      >
        <span
          class="i-lucide-refresh-cw size-4"
          :class="{ 'animate-spin': loading }"
        />
      </button>
    </header>

    <div v-if="provider" class="mb-3 space-y-2 text-xs text-n-slate-11">
      <p>{{ t('SOFTPHONE.PABX.HISTORY_PROVIDER', { provider }) }}</p>
      <p>
        {{
          t('SOFTPHONE.PABX.HISTORY_SYNC', {
            time: sync.last_success_at || '—',
          })
        }}
      </p>
      <p v-if="sync.last_error" role="status">
        {{ t('SOFTPHONE.PABX.HISTORY_ERROR', { code: sync.last_error }) }}
      </p>
    </div>
    <nav v-if="loaded && total > 100" class="mb-3 flex items-center gap-3">
      <button
        type="button"
        :disabled="loading || page <= 1"
        @click="
          page -= 1;
          fetchHistory();
        "
      >
        {{ t('SOFTPHONE.PABX.PREVIOUS') }}
      </button>
      <span>{{ t('SOFTPHONE.PABX.PAGE', { page }) }}</span>
      <button
        type="button"
        :disabled="loading || page * 100 >= total"
        @click="
          page += 1;
          fetchHistory();
        "
      >
        {{ t('SOFTPHONE.PABX.NEXT') }}
      </button>
    </nav>

    <div v-if="loaded" class="mb-4 grid grid-cols-3 gap-2">
      <div
        class="rounded-xl border border-n-blue-7 bg-n-blue-3 p-3 text-n-blue-11"
      >
        <span class="i-lucide-phone size-5" />
        <p class="mt-2 text-xl font-bold">{{ summary.total }}</p>
        <p class="text-[11px] font-medium">{{ TEXT.totalCalls }}</p>
      </div>
      <div
        class="rounded-xl border border-n-teal-7 bg-n-teal-3 p-3 text-n-teal-11"
      >
        <span class="i-lucide-circle-check size-5" />
        <p class="mt-2 text-xl font-bold">{{ summary.answered }}</p>
        <p class="text-[11px] font-medium">{{ TEXT.summaryAnswered }}</p>
      </div>
      <div
        class="rounded-xl border border-n-ruby-7 bg-n-ruby-3 p-3 text-n-ruby-11"
      >
        <span class="i-lucide-phone-missed size-5" />
        <p class="mt-2 text-xl font-bold">{{ summary.unanswered }}</p>
        <p class="text-[11px] font-medium">{{ TEXT.summaryUnanswered }}</p>
      </div>
    </div>

    <div
      class="mb-4 space-y-3 rounded-2xl border border-n-weak bg-n-alpha-1 p-3"
    >
      <div class="flex flex-wrap gap-2">
        <button
          v-for="option in [
            [1, 'Hoje'],
            [7, '7 dias'],
            [30, '30 dias'],
            ['custom', 'Personalizado'],
          ]"
          :key="option[0]"
          type="button"
          class="rounded-lg border px-3 py-2 text-xs font-semibold"
          :class="
            period === option[0]
              ? 'border-n-brand bg-n-brand text-white'
              : 'border-n-weak text-n-slate-11 hover:border-n-brand'
          "
          @click="setPeriod(option[0])"
        >
          {{ option[1] }}
        </button>
      </div>

      <div v-if="period === 'custom'" class="grid grid-cols-2 gap-2">
        <input v-model="customStart" type="date" class="jrc-history-field" />
        <input v-model="customEnd" type="date" class="jrc-history-field" />
      </div>

      <div class="grid grid-cols-2 gap-2">
        <select v-model="direction" class="jrc-history-field">
          <option
            v-for="option in DIRECTION_OPTIONS"
            :key="option[0]"
            :value="option[0]"
          >
            {{ option[1] }}
          </option>
        </select>
        <select v-model="status" class="jrc-history-field">
          <option
            v-for="option in STATUS_OPTIONS"
            :key="option[0]"
            :value="option[0]"
          >
            {{ option[1] }}
          </option>
        </select>
      </div>

      <button
        type="button"
        class="w-full rounded-xl bg-n-brand px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-50"
        :disabled="loading"
        @click="applyFilters"
      >
        {{ actionLabel }}
      </button>
    </div>

    <p
      v-if="errorMessage"
      class="rounded-xl border border-n-ruby-7 bg-n-ruby-3 px-4 py-3 text-sm text-n-ruby-11"
    >
      {{ errorMessage }}
    </p>

    <div
      v-else-if="loading && !loaded"
      class="flex flex-1 flex-col items-center justify-center px-5 text-center"
    >
      <span class="i-lucide-loader-2 mb-3 size-9 animate-spin text-n-brand" />
      <p class="font-medium text-n-slate-11">
        {{ t('SOFTPHONE.PABX.HISTORY_LOADING') }}
      </p>
      <p class="mt-1 text-sm text-n-slate-10">
        {{ t('SOFTPHONE.PABX.HISTORY_LOADING_HELP') }}
      </p>
    </div>

    <div
      v-else-if="!calls.length && !loading"
      class="flex flex-1 items-center justify-center text-center text-sm text-n-slate-10"
    >
      {{ TEXT.empty }}
    </div>

    <div v-else class="min-h-0 flex-1 space-y-2 overflow-y-auto pr-1">
      <article
        v-for="call in sortedCalls"
        :key="call.unique_id || call.id"
        class="rounded-2xl border border-n-weak bg-n-alpha-1 p-4"
      >
        <div class="flex items-start gap-3">
          <span
            class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-xl"
            :class="directionClass(call.direction)"
          >
            <span
              class="size-4"
              :class="[directionMeta(call.direction).icon]"
            />
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p class="text-xs font-semibold text-n-slate-10">
                  {{ directionMeta(call.direction).label }}
                </p>
                <p class="mt-0.5 truncate font-semibold text-n-slate-12">
                  {{ relatedName(call) || callNumber(call) }}
                </p>
                <p
                  v-if="relatedName(call)"
                  class="mt-0.5 truncate text-xs text-n-slate-10"
                >
                  {{ callNumber(call) }}
                </p>
              </div>
              <span
                class="rounded-full border px-2 py-1 text-[11px] font-semibold"
                :class="statusClass(call.status)"
              >
                {{ statusLabel(call.status) }}
              </span>
            </div>
            <p class="mt-2 text-xs text-n-slate-10">
              {{ callTiming(call) }}
            </p>
            <p
              v-if="call.status !== 'answered' && call.hangup_reason"
              class="mt-1 text-xs text-n-slate-10"
            >
              {{ call.hangup_reason }}
            </p>
            <audio
              v-if="call.recording_url"
              class="mt-3 h-9 w-full"
              controls
              controlslist="nodownload noplaybackrate"
              preload="none"
              :src="call.recording_url"
              @contextmenu.prevent
            />
            <button
              v-if="
                call.has_recording &&
                call.provider === 'pabx_v1' &&
                call.recording_state === 'requestable' &&
                !recordings[call.id]
              "
              type="button"
              :disabled="recordingBusy[call.id]"
              class="mt-3 rounded-lg border border-n-weak px-3 py-2 text-xs"
              @click="loadRecording(call)"
            >
              {{ t('SOFTPHONE.PABX.LOAD_RECORDING') }}
            </button>
            <audio
              v-if="recordings[call.id]"
              :src="recordings[call.id]"
              controls
              preload="none"
              class="mt-3 h-9 w-full"
            />
            <p
              v-if="
                call.provider === 'pabx_v1' &&
                call.recording_state === 'mapping_pending'
              "
              class="mt-2 text-xs text-n-slate-10"
            >
              {{ t('SOFTPHONE.PABX.RECORDING_PENDING') }}
            </p>
            <p
              v-if="call.provider === 'pabx_v1' && !call.has_recording"
              class="mt-2 text-xs text-n-slate-10"
            >
              {{ t('SOFTPHONE.PABX.RECORDING_NONE') }}
            </p>
            <p
              v-if="recordingErrors[call.id]"
              role="alert"
              class="mt-2 text-xs text-n-ruby-11"
            >
              {{ recordingErrors[call.id] }}
            </p>
            <div
              v-if="call.recording_url"
              class="mt-3 flex flex-wrap items-center gap-2"
            >
              <button
                type="button"
                class="inline-flex items-center gap-1 rounded-lg border px-3 py-2 text-xs font-semibold disabled:cursor-not-allowed"
                :class="
                  callAnalysis(call)
                    ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-11'
                    : analysisErrorFor(call)
                      ? 'border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11'
                      : 'border-n-brand bg-n-brand text-white'
                "
                :disabled="isAnalyzing(call) || !!callAnalysis(call)"
                @click="analyzeCall(call)"
              >
                <span
                  class="size-3.5"
                  :class="
                    isAnalyzing(call)
                      ? 'i-lucide-loader-2 animate-spin'
                      : callAnalysis(call)
                        ? 'i-lucide-check'
                        : analysisErrorFor(call)
                          ? 'i-lucide-alert-triangle'
                          : 'i-lucide-sparkles'
                  "
                />
                {{ qualityButtonLabel(call) }}
              </button>
              <button
                v-if="callAnalysis(call)"
                type="button"
                class="inline-flex items-center gap-1 rounded-lg border border-n-weak bg-n-alpha-1 px-3 py-2 text-xs font-semibold text-n-slate-11 hover:border-n-brand hover:text-n-brand"
                @click="toggleAnalysis(call)"
              >
                <span class="i-lucide-clipboard-list size-3.5" />
                {{
                  isAnalysisOpen(call) ? TEXT.hideAnalysis : TEXT.viewAnalysis
                }}
              </button>
            </div>
            <p
              v-if="analysisErrorFor(call)"
              class="mt-2 rounded-lg border border-n-ruby-7 bg-n-ruby-3 px-3 py-2 text-xs text-n-ruby-11"
            >
              {{ analysisErrorFor(call) }}
            </p>
            <div
              v-if="isAnalysisOpen(call) && callAnalysis(call)"
              class="mt-3 rounded-xl border border-n-weak bg-n-alpha-2 p-3"
            >
              <div class="grid grid-cols-2 gap-2">
                <div
                  v-for="metric in analysisMetrics(callAnalysis(call))"
                  :key="metric[0]"
                  class="rounded-lg bg-n-alpha-1 px-3 py-2"
                >
                  <p class="text-[10px] font-semibold uppercase text-n-slate-9">
                    {{ metric[0] }}
                  </p>
                  <p
                    class="mt-1 text-xs font-semibold capitalize text-n-slate-12"
                  >
                    {{ formatValue(metric[1]) }}
                  </p>
                </div>
              </div>
              <p class="mt-3 text-xs font-semibold text-n-slate-12">
                {{ TEXT.analysisSummary }}
              </p>
              <p class="mt-1 text-xs leading-5 text-n-slate-10">
                {{ formatValue(callAnalysis(call).resumo_conversa) }}
              </p>
              <p
                v-if="callAnalysis(call).alerta_supervisao"
                class="mt-3 rounded-lg border border-n-amber-7 bg-n-amber-3 px-3 py-2 text-xs text-n-amber-11"
              >
                {{ formatValue(callAnalysis(call).motivo_alerta) }}
              </p>
            </div>
            <p v-if="call.id" class="mt-2 text-[10px] text-n-slate-9">
              {{ `ID ${call.id}` }}
            </p>
          </div>
        </div>
      </article>
    </div>

    <p v-if="fetchedAt" class="mt-3 text-right text-[11px] text-n-slate-9">
      {{ updatedText }}
    </p>
  </aside>
</template>

<style scoped>
.jrc-history-field {
  @apply h-10 min-w-0 rounded-lg border border-n-weak bg-n-alpha-1 px-3 text-xs text-n-slate-12 outline-none;
}

.jrc-history-field:focus {
  @apply border-n-brand;
}
</style>
