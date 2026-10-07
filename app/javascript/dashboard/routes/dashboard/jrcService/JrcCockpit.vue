<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import jrcAiAPI from 'dashboard/api/jrcAi';
import CockpitHero from './CockpitHero.vue';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const currentUser = useMapGetter('getCurrentUser');
const inboxes = useMapGetter('inboxes/getInboxes');
const getInboxUnreadCount = useMapGetter(
  'conversationUnreadCounts/getInboxUnreadCount'
);
const { openWithPrompt } = useJrcCopilot();

const loading = ref(false);
const error = ref('');
const period = ref('today');
const showPersonalize = ref(false);
const visibleSections = ref({
  summary: true,
  quickLinks: true,
  attention: true,
  channels: true,
  aiAgents: true,
  team: true,
});
const data = ref({
  profile: 'agent',
  generated_at: null,
  summary: {},
  attention: [],
  channel_distribution: [],
  daily_volume: [],
  team: {},
  ai_agents: [],
  usage: {},
});
let refreshTimer;

const isSupervisor = computed(() => data.value.profile === 'supervisor');
const canConfigureAi = computed(() => isSupervisor.value);
const aiConfigured = computed(
  () => Number(data.value.usage?.providers_configured || 0) > 0
);
const displayName = computed(
  () => currentUser.value?.name || currentUser.value?.email || 'Usuário'
);
const firstName = computed(() => displayName.value.split(' ')[0]);
const profileTitle = computed(() =>
  isSupervisor.value ? 'Operação geral' : 'Meu dia'
);
const profileDescription = computed(() =>
  isSupervisor.value
    ? 'Filas, equipe, SLA, produtividade e alertas da operação.'
    : 'Suas prioridades, atendimentos, retornos e desempenho de hoje.'
);

const emailInboxes = computed(() =>
  (inboxes.value || []).filter(inbox =>
    String(inbox.channel_type || inbox.channelType || '')
      .toLowerCase()
      .includes('email')
  )
);
const emailUnreadCount = computed(() =>
  emailInboxes.value.reduce(
    (total, inbox) => total + Number(getInboxUnreadCount.value(inbox.id) || 0),
    0
  )
);

const formatNumber = value =>
  value == null ? '--' : new Intl.NumberFormat('pt-BR').format(Number(value));
const formatPercent = value =>
  value === null || value === undefined ? '--' : `${value}%`;
const formatDuration = seconds => {
  if (seconds === null || seconds === undefined) return '--:--:--';
  const total = Math.max(0, Number(seconds || 0));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const remaining = Math.floor(total % 60);
  return [hours, minutes, remaining]
    .map(value => String(value).padStart(2, '0'))
    .join(':');
};
const formatUpdated = value => {
  if (!value) return 'Aguardando atualização';
  return new Intl.DateTimeFormat('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).format(new Date(value));
};

const summaryCards = computed(() => {
  const summary = data.value.summary || {};
  return [
    {
      key: 'open',
      label: 'Conversas em aberto',
      value: formatNumber(summary.conversations_open),
      detail: `${formatNumber(summary.conversations_waiting)} aguardando`,
      icon: 'i-lucide-messages-square',
      tone: 'blue',
      route: 'home',
    },
    {
      key: 'email',
      label: 'E-mails não lidos',
      value: formatNumber(emailUnreadCount.value),
      detail: `${formatNumber(summary.emails_open)} em atendimento`,
      icon: 'i-lucide-mail',
      tone: 'amber',
      route: 'jrc_email_center',
    },
    {
      key: 'calls',
      label: 'Ligações em andamento',
      value: formatNumber(summary.calls_in_progress),
      detail: `${formatNumber(summary.missed_calls)} perdida(s)`,
      icon: 'i-lucide-phone-call',
      tone: summary.missed_calls > 0 ? 'rose' : 'teal',
      route: 'jrc_calls_center',
    },
    {
      key: 'tasks',
      label: 'Tarefas pendentes',
      value: formatNumber(summary.pending_tasks),
      detail: `${formatNumber(summary.overdue_returns)} retorno(s) vencido(s)`,
      icon: 'i-lucide-list-checks',
      tone: 'violet',
      route: 'crm_activities',
    },
    {
      key: 'sla',
      label: 'SLA operacional',
      value: formatPercent(summary.sla_estimated_percent),
      detail: `${formatNumber(summary.sla_risk_count)} em risco`,
      icon: 'i-lucide-gauge',
      tone: summary.sla_risk_count > 0 ? 'amber' : 'teal',
      route: 'operational_live_reports',
    },
  ];
});

const operationalCards = computed(() => {
  const summary = data.value.summary || {};
  return [
    {
      label: 'Agendamentos hoje',
      value: formatNumber(summary.appointments_today),
      icon: 'i-lucide-calendar-check',
      tone: 'violet',
    },
    {
      label: 'Resposta média',
      value: formatDuration(summary.average_first_response_seconds),
      icon: 'i-lucide-timer',
      tone: 'blue',
    },
    {
      label: 'Resolução média',
      value: formatDuration(summary.average_resolution_seconds),
      icon: 'i-lucide-circle-check-big',
      tone: 'teal',
    },
    {
      label: 'CSAT',
      value: formatPercent(summary.csat_percent),
      icon: 'i-lucide-smile',
      tone: 'emerald',
    },
    {
      label: isSupervisor.value ? 'Sem responsável' : 'Leads ativos',
      value: formatNumber(
        isSupervisor.value
          ? summary.unassigned_conversations
          : summary.active_leads
      ),
      icon: isSupervisor.value
        ? 'i-lucide-user-round-x'
        : 'i-lucide-user-round-plus',
      tone: 'cyan',
    },
  ];
});

const quickLinks = computed(() => {
  const summary = data.value.summary || {};
  return [
    {
      label: 'Conversas',
      description: 'WhatsApp, Instagram, Facebook, webchat e demais canais.',
      value: summary.conversations_open,
      icon: 'i-lucide-message-circle',
      tone: 'blue',
      route: 'home',
    },
    {
      label: 'E-mails',
      description: 'Caixas de e-mail, pendências e histórico do cliente.',
      value: emailUnreadCount.value,
      icon: 'i-lucide-mail-open',
      tone: 'amber',
      route: 'jrc_email_center',
    },
    {
      label: 'Ligações',
      description: 'Telefonia, Ramal JRC, retornos e histórico de chamadas.',
      value: summary.calls_in_progress,
      icon: 'i-lucide-phone-call',
      tone: 'teal',
      route: 'jrc_calls_center',
    },
    {
      label: 'WhatsApp Calling',
      description: 'Chamadas recebidas e realizadas pelo WhatsApp.',
      value: summary.whatsapp_calls,
      icon: 'i-ri-whatsapp-fill',
      tone: 'emerald',
      route: 'whatsapp_calling_index',
    },
    {
      label: 'Contatos',
      description: 'Pessoas, empresas e histórico de relacionamentos.',
      value: null,
      icon: 'i-lucide-contact-round',
      tone: 'violet',
      route: 'contacts_dashboard_index',
    },
    {
      label: 'Canais',
      description: 'Caixas e canais configurados para esta conta.',
      value: summary.active_channels,
      icon: 'i-lucide-radio-tower',
      tone: 'cyan',
      route: 'settings_inbox_list',
    },
  ];
});

const personalizationItems = computed(() => {
  const items = [
    { key: 'summary', label: 'Resumo e indicadores' },
    { key: 'quickLinks', label: 'Acessos operacionais' },
    { key: 'attention', label: 'Prioridades e evolução' },
    { key: 'channels', label: 'Canais e capacidade' },
  ];
  if (aiConfigured.value) {
    items.push({ key: 'aiAgents', label: 'Agentes de IA' });
  }
  return items;
});

const toneClasses = tone =>
  ({
    blue: 'border-n-blue-6 bg-n-blue-2 text-n-blue-11',
    amber: 'border-n-amber-6 bg-n-amber-2 text-n-amber-11',
    rose: 'border-n-ruby-6 bg-n-ruby-2 text-n-ruby-11',
    violet: 'border-n-violet-6 bg-n-violet-2 text-n-violet-11',
    teal: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
    emerald: 'border-n-teal-6 bg-n-teal-2 text-n-teal-11',
    cyan: 'border-n-blue-6 bg-n-blue-2 text-n-blue-11',
  })[tone] || 'border-n-weak bg-n-slate-2 text-n-slate-12';

const statusClasses = status =>
  ({
    active: 'bg-n-teal-3 text-n-teal-11',
    attention: 'bg-n-amber-3 text-n-amber-11',
    ready: 'bg-n-blue-3 text-n-blue-11',
    idle: 'bg-n-slate-3 text-n-slate-11',
    restricted: 'bg-n-violet-3 text-n-violet-11',
  })[status] || 'bg-n-slate-3 text-n-slate-11';
const statusLabel = status =>
  ({
    not_run: 'Ainda não executado',
    queued: 'Na fila',
    running: 'Em análise',
    completed: 'Concluído',
    failed: 'Falhou',
    cancelled: 'Cancelado',
    active: 'Ativo',
    attention: 'Atenção',
    ready: 'Pronto',
    idle: 'Em espera',
    restricted: 'Restrito',
  })[status] || status;

const totalChannels = computed(() =>
  data.value.channel_distribution.reduce(
    (total, item) => total + Number(item.count || 0),
    0
  )
);
const channelColors = [
  '#10a66a',
  '#087ff5',
  '#7758e8',
  '#f59e0b',
  '#ef476f',
  '#00a6a6',
  '#64748b',
];
const donutStyle = computed(() => {
  if (!totalChannels.value) {
    return { background: 'conic-gradient(#e5e7eb 0 100%)' };
  }
  let cursor = 0;
  const pieces = data.value.channel_distribution.map((item, index) => {
    const start = cursor;
    const end = cursor + (Number(item.count || 0) / totalChannels.value) * 100;
    cursor = end;
    return `${channelColors[index % channelColors.length]} ${start}% ${end}%`;
  });
  return { background: `conic-gradient(${pieces.join(',')})` };
});

const chartPoints = computed(() => {
  const rows = data.value.daily_volume || [];
  if (!rows.length) return '';
  const max = Math.max(1, ...rows.map(row => Number(row.conversations || 0)));
  return rows
    .map((row, index) => {
      const x = rows.length === 1 ? 50 : (index / (rows.length - 1)) * 100;
      const y = 88 - (Number(row.conversations || 0) / max) * 72;
      return `${x},${y}`;
    })
    .join(' ');
});

const loadCockpit = async () => {
  loading.value = true;
  error.value = '';
  try {
    const response = await jrcAiAPI.cockpit(period.value);
    data.value = response.data;
  } catch (requestError) {
    error.value =
      requestError?.response?.data?.error ||
      'Não foi possível carregar o Cockpit.';
  } finally {
    loading.value = false;
  }
};

const openRoute = name => {
  if (!name) return;
  router.push({ name, params: { accountId: route.params.accountId } });
};
const openAttention = item => openRoute(item.route_name || 'jrc_cockpit');
const analyzeAttention = item => {
  if (!aiConfigured.value) return;
  openWithPrompt(`Organize a prioridade: ${item.title}. ${item.description}`);
};
const askAgent = agent => {
  if (!aiConfigured.value) return;
  openWithPrompt(agent.prompt);
};
const savePreferences = () => {
  window.localStorage.setItem(
    'jrc_cockpit_sections',
    JSON.stringify(visibleSections.value)
  );
  showPersonalize.value = false;
};
const restorePreferences = () => {
  try {
    const saved = JSON.parse(
      window.localStorage.getItem('jrc_cockpit_sections') || 'null'
    );
    if (saved) {
      visibleSections.value = { ...visibleSections.value, ...saved };
    }
  } catch {
    // Keep defaults when a saved preference is invalid.
  }
};

watch(period, loadCockpit);
onMounted(() => {
  restorePreferences();
  store.dispatch('inboxes/get');
  store.dispatch('conversationUnreadCounts/get');
  loadCockpit();
  refreshTimer = window.setInterval(loadCockpit, 60000);
});
onBeforeUnmount(() => window.clearInterval(refreshTimer));
</script>

<template>
  <main
    class="h-full overflow-auto bg-gradient-to-br from-n-blue-2 to-n-background text-n-slate-12 p-4 sm:p-5"
  >
    <div class="mx-auto max-w-[1750px] space-y-4">
      <CockpitHero
        :name="firstName"
        :description="`${profileTitle} · ${profileDescription}`"
        :summary="data.summary"
        :attention="data.attention"
        :ready="!!data.generated_at && !error"
        :loading="loading"
      >
        <p class="mb-0 text-xs text-white/90">
          Atualizado às {{ formatUpdated(data.generated_at) }}
        </p>
        <div class="flex flex-wrap items-center gap-2">
          <select
            v-model="period"
            class="h-11 w-auto rounded-xl border border-white/20 bg-white/10 px-4 text-sm font-semibold text-white outline-none backdrop-blur [&>option]:text-n-slate-12 [&>option]:bg-n-solid-2"
          >
            <option value="today">Hoje</option>
            <option value="7_days">Últimos 7 dias</option>
            <option value="30_days">Últimos 30 dias</option>
          </select>
          <button
            type="button"
            class="inline-flex h-11 items-center gap-2 rounded-xl bg-n-solid-2 px-4 text-sm font-semibold text-n-blue-11 shadow"
            @click="showPersonalize = true"
          >
            <i class="i-lucide-sliders-horizontal size-4" /> Personalizar
            Cockpit
          </button>
          <button
            type="button"
            class="grid size-11 place-content-center rounded-xl bg-white/10 transition hover:bg-white/20"
            :disabled="loading"
            title="Atualizar"
            @click="loadCockpit"
          >
            <i
              class="i-lucide-refresh-cw size-5"
              :class="{ 'animate-spin': loading }"
            />
          </button>
        </div>
      </CockpitHero>

      <div
        v-if="error"
        class="flex items-center justify-between rounded-2xl border border-n-ruby-6 bg-n-ruby-2 p-4 text-sm text-n-ruby-11"
      >
        <span>{{ error }}</span>
        <button class="font-semibold underline" @click="loadCockpit">
          Tentar novamente
        </button>
      </div>

      <section
        v-if="visibleSections.summary"
        class="grid gap-3 sm:grid-cols-2 xl:grid-cols-5"
      >
        <button
          v-for="card in summaryCards"
          :key="card.key"
          type="button"
          class="group rounded-2xl border bg-n-solid-2 p-4 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          :class="toneClasses(card.tone).split(' ')[0]"
          @click="openRoute(card.route)"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="truncate text-xs font-semibold text-n-slate-11">
                {{ card.label }}
              </p>
              <strong
                class="mt-3 block text-3xl"
                :class="toneClasses(card.tone).split(' ')[2]"
              >
                {{ card.value }}
              </strong>
            </div>
            <span
              class="grid size-10 shrink-0 place-content-center rounded-xl border"
              :class="toneClasses(card.tone)"
            >
              <i class="size-5" :class="card.icon" />
            </span>
          </div>
          <p class="mt-3 text-xs font-semibold text-n-slate-11">
            {{ card.detail }} →
          </p>
        </button>
      </section>

      <section
        v-if="visibleSections.summary"
        class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5"
      >
        <article
          v-for="card in operationalCards"
          :key="card.label"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
        >
          <div class="flex items-center gap-3">
            <span
              class="grid size-9 place-content-center rounded-xl border"
              :class="toneClasses(card.tone)"
            >
              <i class="size-4" :class="card.icon" />
            </span>
            <div>
              <p class="text-xs text-n-slate-11">{{ card.label }}</p>
              <strong
                class="text-xl"
                :class="toneClasses(card.tone).split(' ')[2]"
                >{{ card.value }}</strong
              >
            </div>
          </div>
        </article>
      </section>

      <section
        v-if="visibleSections.quickLinks"
        class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
      >
        <div>
          <h2 class="text-lg font-bold text-n-slate-12">
            Acessos operacionais
          </h2>
          <p class="text-sm text-n-slate-11">
            O Cockpit organiza a operação e direciona para os módulos que já
            executam cada tarefa.
          </p>
        </div>
        <div class="mt-4 grid gap-3 md:grid-cols-2 xl:grid-cols-6">
          <button
            v-for="link in quickLinks"
            :key="link.label"
            type="button"
            class="rounded-2xl border p-4 text-left transition hover:-translate-y-0.5 hover:shadow-md"
            :class="toneClasses(link.tone)"
            @click="openRoute(link.route)"
          >
            <div class="flex items-start justify-between gap-2">
              <span
                class="grid size-10 place-content-center rounded-xl bg-n-solid-2"
              >
                <i class="size-5" :class="link.icon" />
              </span>
              <strong
                v-if="link.value !== null && link.value !== undefined"
                class="text-lg text-n-slate-12"
              >
                {{ formatNumber(link.value) }}
              </strong>
            </div>
            <h3 class="mt-3 font-bold text-n-slate-12">{{ link.label }}</h3>
            <p class="mt-1 text-xs leading-5 text-n-slate-11">
              {{ link.description }}
            </p>
            <span class="mt-3 inline-block text-xs font-semibold">
              Abrir →
            </span>
          </button>
        </div>
      </section>

      <section
        v-if="visibleSections.attention"
        class="grid gap-4 xl:grid-cols-[1.25fr_0.75fr]"
      >
        <article
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <div class="flex items-center justify-between gap-3">
            <div>
              <h2 class="text-lg font-bold text-n-slate-12">
                O que precisa da minha atenção
              </h2>
              <p class="text-sm text-n-slate-11">
                Prioridades calculadas com os dados atuais da operação.
              </p>
            </div>
            <button
              v-if="aiConfigured"
              class="rounded-xl bg-n-brand px-4 py-2 text-xs font-semibold text-white"
              @click="
                openWithPrompt(
                  'O que precisa da minha atenção agora? Organize por urgência e explique a próxima ação.'
                )
              "
            >
              Organizar com IA
            </button>
          </div>
          <div class="mt-4 grid gap-3 md:grid-cols-2">
            <article
              v-for="item in data.attention"
              :key="item.key"
              class="flex items-start gap-3 rounded-2xl border p-4"
              :class="
                item.severity === 'high'
                  ? 'border-n-ruby-6 bg-n-ruby-2'
                  : item.severity === 'medium'
                    ? 'border-n-amber-6 bg-n-amber-2'
                    : 'border-n-teal-6 bg-n-teal-2'
              "
            >
              <span
                class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-solid-2"
              >
                <i
                  class="size-5"
                  :class="
                    item.severity === 'high'
                      ? 'i-lucide-triangle-alert text-n-ruby-11'
                      : item.severity === 'medium'
                        ? 'i-lucide-clock-alert text-n-amber-11'
                        : 'i-lucide-circle-check text-n-teal-11'
                  "
                />
              </span>
              <div class="min-w-0 flex-1">
                <div class="flex items-center justify-between gap-2">
                  <b class="text-sm text-n-slate-12">{{ item.title }}</b>
                  <strong class="text-lg text-n-slate-12">
                    {{ item.count }}
                  </strong>
                </div>
                <small class="mt-1 block text-n-slate-11">
                  {{ item.description }}
                </small>
                <div class="mt-3 flex flex-wrap gap-2">
                  <button
                    type="button"
                    class="rounded-lg bg-n-brand px-3 py-2 text-xs font-semibold text-white"
                    @click="openAttention(item)"
                  >
                    Abrir e agir
                  </button>
                  <button
                    v-if="aiConfigured"
                    type="button"
                    class="rounded-lg border border-n-violet-6 bg-n-solid-2 px-3 py-2 text-xs font-semibold text-n-violet-11"
                    @click="analyzeAttention(item)"
                  >
                    Analisar com IA
                  </button>
                </div>
              </div>
            </article>
          </div>
        </article>

        <article
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <div class="flex items-center justify-between">
            <div>
              <h2 class="font-bold text-n-slate-12">
                Evolução dos atendimentos
              </h2>
              <p class="text-xs text-n-slate-11">
                Conversas criadas nos últimos 7 dias
              </p>
            </div>
            <i class="i-lucide-chart-no-axes-combined size-5 text-n-blue-11" />
          </div>
          <div
            class="mt-5 h-44 rounded-2xl bg-gradient-to-b from-n-blue-2 to-n-solid-2 p-3"
          >
            <svg
              viewBox="0 0 100 100"
              preserveAspectRatio="none"
              class="h-full w-full overflow-visible"
            >
              <line
                v-for="y in [20, 40, 60, 80]"
                :key="y"
                x1="0"
                :y1="y"
                x2="100"
                :y2="y"
                stroke="#dbeafe"
                stroke-width="0.7"
              />
              <polyline
                v-if="chartPoints"
                :points="chartPoints"
                fill="none"
                stroke="#087ff5"
                stroke-width="3"
                stroke-linecap="round"
                stroke-linejoin="round"
                vector-effect="non-scaling-stroke"
              />
            </svg>
          </div>
          <div class="mt-2 flex justify-between text-[10px] text-n-slate-11">
            <span v-for="row in data.daily_volume" :key="row.date">
              {{ row.date.slice(5).split('-').reverse().join('/') }}
            </span>
          </div>
        </article>
      </section>

      <section
        v-if="visibleSections.channels"
        class="grid gap-4 xl:grid-cols-3"
      >
        <article
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <h2 class="font-bold text-n-slate-12">Atendimentos por canal</h2>
          <div class="mt-5 flex items-center gap-6">
            <div
              class="relative size-40 shrink-0 rounded-full"
              :style="donutStyle"
            >
              <div
                class="absolute inset-7 grid place-content-center rounded-full bg-n-solid-2 text-center"
              >
                <strong class="text-2xl text-n-slate-12">
                  {{ totalChannels }}
                </strong>
                <span class="text-[10px] text-n-slate-11">Em aberto</span>
              </div>
            </div>
            <div class="min-w-0 flex-1 space-y-2">
              <div
                v-for="(item, index) in data.channel_distribution"
                :key="item.channel"
                class="flex items-center justify-between gap-3 text-xs"
              >
                <span class="flex min-w-0 items-center gap-2">
                  <i
                    class="size-2 shrink-0 rounded-full"
                    :style="{
                      backgroundColor:
                        channelColors[index % channelColors.length],
                    }"
                  />
                  <span class="truncate text-n-slate-11">
                    {{ item.channel }}
                  </span>
                </span>
                <b class="text-n-slate-12">{{ item.count }}</b>
              </div>
              <p
                v-if="!data.channel_distribution.length"
                class="text-sm text-n-slate-11"
              >
                Nenhum atendimento em aberto.
              </p>
            </div>
          </div>
        </article>

        <article
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <h2 class="font-bold text-n-slate-12">Capacidade da equipe</h2>
          <p class="text-xs text-n-slate-11">
            {{
              isSupervisor
                ? 'Visão geral dos agentes'
                : 'Seu status operacional'
            }}
          </p>
          <div class="mt-5 space-y-4">
            <div
              v-for="item in [
                {
                  key: 'online',
                  label: 'Disponíveis',
                  tone: 'bg-n-teal-20',
                },
                { key: 'busy', label: 'Ocupados', tone: 'bg-n-amber-20' },
                { key: 'offline', label: 'Offline', tone: 'bg-slate-400' },
              ]"
              :key="item.key"
            >
              <div class="mb-1 flex justify-between text-xs">
                <span class="text-n-slate-11">{{ item.label }}</span>
                <b class="text-n-slate-12">{{ data.team[item.key] || 0 }}</b>
              </div>
              <div class="h-2 rounded-full bg-n-slate-3">
                <div
                  class="h-2 rounded-full"
                  :class="item.tone"
                  :style="{
                    width: `${Math.min(
                      100,
                      ((data.team[item.key] || 0) /
                        Math.max(1, data.summary.total_agents || 1)) *
                        100
                    )}%`,
                  }"
                />
              </div>
            </div>
          </div>
        </article>

        <article
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <div class="flex items-center justify-between">
            <div>
              <h2 class="font-bold text-n-slate-12">Inteligência Artificial</h2>
              <p class="text-xs text-n-slate-11">
                Recurso opcional administrado pela própria conta
              </p>
            </div>
            <i class="i-lucide-brain-circuit size-6 text-n-violet-11" />
          </div>

          <template v-if="aiConfigured">
            <div class="mt-5 grid grid-cols-2 gap-3">
              <div class="rounded-xl bg-n-violet-2 p-3">
                <span class="text-xs text-n-violet-11">Tokens hoje</span>
                <strong class="mt-1 block text-xl text-n-slate-12">
                  {{ formatNumber(data.usage.tokens_today) }}
                </strong>
              </div>
              <div class="rounded-xl bg-n-blue-2 p-3">
                <span class="text-xs text-n-blue-11">Tokens no mês</span>
                <strong class="mt-1 block text-xl text-n-slate-12">
                  {{ formatNumber(data.usage.tokens_month) }}
                </strong>
              </div>
              <div class="col-span-2 rounded-xl bg-n-teal-2 p-3">
                <span class="text-xs text-n-teal-11">
                  Provedores configurados
                </span>
                <strong class="mt-1 block text-xl text-n-slate-12">
                  {{ formatNumber(data.usage.providers_configured) }}
                </strong>
              </div>
            </div>
            <button
              class="mt-4 w-full rounded-xl border border-n-violet-6 px-4 py-2.5 text-xs font-semibold text-n-violet-11"
              @click="
                openRoute(canConfigureAi ? 'jrc_ai_providers' : 'jrc_ai_agents')
              "
            >
              {{ canConfigureAi ? 'Administrar IA' : 'Ver Agentes IA' }} →
            </button>
          </template>

          <template v-else>
            <div class="mt-5 rounded-2xl bg-n-slate-2 p-4">
              <div class="flex items-start gap-3">
                <span
                  class="grid size-10 shrink-0 place-content-center rounded-xl bg-n-solid-2 text-n-slate-11"
                >
                  <i class="i-lucide-power size-5" />
                </span>
                <div>
                  <h3 class="text-sm font-bold text-n-slate-12">
                    IA não configurada
                  </h3>
                  <p class="mt-1 text-xs leading-5 text-n-slate-11">
                    O Cockpit, Conversas, CRM, Agenda, Ligações e WhatsApp
                    Calling continuam funcionando normalmente sem IA.
                  </p>
                </div>
              </div>
            </div>
            <button
              v-if="canConfigureAi"
              class="mt-4 w-full rounded-xl bg-violet-600 px-4 py-2.5 text-xs font-semibold text-white"
              @click="openRoute('jrc_ai_providers')"
            >
              Configurar Inteligência Artificial
            </button>
            <p v-else class="mt-4 text-xs text-n-slate-11">
              A configuração de provedor e credencial pertence ao administrador
              desta conta.
            </p>
          </template>
        </article>
      </section>

      <section
        v-if="visibleSections.aiAgents && aiConfigured"
        class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
      >
        <div
          class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
        >
          <div>
            <h2 class="text-lg font-bold text-n-slate-12">
              Agentes IA trabalhando para você
            </h2>
            <p class="text-sm text-n-slate-11">
              Especialistas analisam a operação e entregam recomendações ao
              Copiloto JRC.
            </p>
          </div>
          <button
            class="rounded-xl bg-gradient-to-r from-violet-600 to-blue-600 px-4 py-2.5 text-xs font-semibold text-white"
            @click="openRoute('jrc_ai_agents')"
          >
            Ver Central de Agentes IA
          </button>
        </div>
        <div class="mt-5 grid gap-3 md:grid-cols-2 xl:grid-cols-4">
          <button
            v-for="agent in data.ai_agents"
            :key="agent.key"
            type="button"
            class="rounded-2xl border border-n-weak p-4 text-left transition hover:-translate-y-0.5 hover:border-blue-300 hover:shadow-md"
            @click="askAgent(agent)"
          >
            <div class="flex items-start justify-between gap-2">
              <span
                class="grid size-10 place-content-center rounded-xl bg-gradient-to-br from-cyan-50 to-violet-50 text-n-blue-11"
              >
                <i class="i-lucide-bot size-5" />
              </span>
              <span
                class="rounded-full px-2 py-1 text-[10px] font-bold uppercase"
                :class="statusClasses(agent.status)"
              >
                {{ statusLabel(agent.status) }}
              </span>
            </div>
            <h3 class="mt-3 font-bold text-n-slate-12">{{ agent.name }}</h3>
            <p class="mt-1 text-xs leading-5 text-n-slate-11">
              {{ agent.description }}
            </p>
            <p
              class="mt-3 rounded-xl bg-n-slate-2 p-2.5 text-xs font-medium text-n-slate-12"
            >
              {{ agent.last_result }}
            </p>
            <span
              class="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-n-blue-11"
            >
              Pedir análise <i class="i-lucide-arrow-up-right size-3" />
            </span>
          </button>
        </div>
      </section>
    </div>

    <div
      v-if="showPersonalize"
      class="fixed inset-0 z-[80] grid place-content-center bg-slate-950/40 p-4"
      @click.self="showPersonalize = false"
    >
      <section
        class="max-h-[calc(100dvh-2rem)] w-full max-w-md overflow-y-auto overscroll-contain rounded-3xl bg-n-solid-2 p-6 shadow-2xl"
      >
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-lg font-bold text-n-slate-12">
              Personalizar Cockpit
            </h2>
            <p class="text-xs text-n-slate-11">
              Escolha os blocos visíveis para este usuário.
            </p>
          </div>
          <button
            class="grid size-9 shrink-0 place-content-center rounded-xl bg-n-slate-3 text-n-slate-12 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="t('GENERAL.CLOSE')"
            @click="showPersonalize = false"
          >
            <i class="i-lucide-x size-4" />
          </button>
        </div>
        <div class="mt-5 space-y-3">
          <label
            v-for="item in personalizationItems"
            :key="item.key"
            class="flex items-center justify-between rounded-xl border border-n-weak p-3"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ item.label }}
            </span>
            <input
              v-model="visibleSections[item.key]"
              type="checkbox"
              class="size-4 accent-blue-600"
            />
          </label>
        </div>
        <button
          class="mt-5 w-full rounded-xl bg-n-brand py-3 text-sm font-semibold text-white"
          @click="savePreferences"
        >
          Salvar preferências
        </button>
      </section>
    </div>
  </main>
</template>
