<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import jrcAiAPI from 'dashboard/api/jrcAi';
import { useJrcCopilot } from 'dashboard/components-next/jrcCopilot/useJrcCopilot';
import { usePolicy } from 'dashboard/composables/usePolicy';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const { checkPermissions } = usePolicy();
const canManageProviders = computed(() => checkPermissions(['administrator']));
// This public asset is served by Rails, outside Vite's module graph.
const agentIllustration = '/brand-assets/jrc-copilot-thinking.png';

const loading = ref(false);
const error = ref('');
const payload = ref({
  agents: [],
  attention: [],
  profile: 'agent',
  generated_at: null,
});

const load = async () => {
  loading.value = true;
  error.value = '';
  try {
    const response = await jrcAiAPI.agents();
    payload.value = response.data;
  } catch (requestError) {
    error.value =
      requestError?.response?.data?.error ||
      'Nao foi possivel carregar os agentes de IA.';
  } finally {
    loading.value = false;
  }
};
const statusClasses = status =>
  ({
    active: 'bg-emerald-100 text-emerald-700',
    attention: 'bg-amber-100 text-amber-700',
    ready: 'bg-blue-100 text-blue-700',
    idle: 'bg-slate-100 text-slate-600',
    restricted: 'bg-violet-100 text-violet-700',
  })[status] || 'bg-slate-100 text-slate-600';
const statusLabel = status =>
  ({
    not_run: 'Ainda não executado',
    queued: 'Na fila',
    running: 'Em análise',
    completed: 'Concluído',
    failed: 'Falhou',
    cancelled: 'Cancelado',
    active: 'Ativo',
    attention: 'Atencao',
    ready: 'Pronto',
    idle: 'Em espera',
    restricted: 'Restrito',
  })[status] || status;
const openSettings = () =>
  router.push({
    name: 'jrc_ai_providers',
    params: { accountId: route.params.accountId },
  });
const selectAgent = agent => {
  sessionStorage.setItem('jrcNicoPreferredAgent', agent.key);
  useJrcCopilot().close();
  router.push({ name: 'home', params: { accountId: route.params.accountId } });
};

onMounted(load);
</script>

<template>
  <main
    class="h-full overflow-auto bg-[linear-gradient(135deg,#f3f7fc,#eef6ff)] p-4 sm:p-5"
  >
    <div class="mx-auto max-w-[1500px] space-y-4">
      <header
        class="relative overflow-hidden rounded-3xl bg-gradient-to-r from-[#062f57] via-[#075a87] to-[#7758e8] p-6 text-white shadow-lg"
      >
        <div class="relative z-10 max-w-3xl">
          <span
            class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-[11px] font-bold uppercase"
            ><i class="i-lucide-brain-circuit size-4" /> Inteligencia
            operacional</span
          >
          <h1 class="mt-3 text-3xl font-bold">Central de Agentes IA</h1>
          <p class="mt-2 text-sm leading-6 text-blue-50/90">
            {{ t('JRC_NICO.CENTRAL_DESCRIPTION') }}
          </p>
        </div>
        <img
          :src="agentIllustration"
          alt="Copiloto JRC"
          class="pointer-events-none absolute -bottom-24 right-8 hidden w-64 opacity-90 lg:block"
        />
      </header>

      <div
        class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-[#dbe7f5] bg-white p-4 shadow-sm"
      >
        <div>
          <b class="text-sm text-[#172033]"
            >Perfil atual:
            {{
              payload.profile === 'supervisor'
                ? 'Supervisor / Administrador'
                : 'Agente'
            }}</b
          >
          <p class="text-xs text-[#667085]">
            As analises respeitam o escopo e as permissoes do usuario.
          </p>
        </div>
        <div class="flex gap-2">
          <button
            v-if="canManageProviders"
            class="rounded-xl border border-violet-200 px-4 py-2 text-xs font-semibold text-violet-700"
            @click="openSettings"
          >
            Configurar provedores</button
          ><button
            class="grid size-9 place-content-center rounded-xl bg-blue-50 text-blue-700"
            :disabled="loading"
            @click="load"
          >
            <i
              class="i-lucide-refresh-cw size-4"
              :class="{ 'animate-spin': loading }"
            />
          </button>
        </div>
      </div>

      <div
        v-if="error"
        class="rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700"
      >
        {{ error }}
      </div>

      <section class="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <article
          v-for="agent in payload.agents"
          :key="agent.key"
          class="flex min-h-64 flex-col rounded-2xl border border-[#dfe7f2] bg-white p-5 shadow-sm"
        >
          <div class="flex items-start justify-between gap-3">
            <span
              class="grid size-12 place-content-center rounded-2xl bg-gradient-to-br from-cyan-50 to-violet-100 text-[#075a87]"
              ><i class="i-lucide-bot size-6" /></span
            ><span
              class="rounded-full px-2.5 py-1 text-[10px] font-bold uppercase"
              :class="statusClasses(agent.status)"
              >{{ statusLabel(agent.status) }}</span
            >
          </div>
          <h2 class="mt-4 text-lg font-bold text-[#172033]">
            {{ agent.name }}
          </h2>
          <p class="mt-1 text-sm leading-5 text-[#667085]">
            {{ agent.description }}
          </p>
          <div class="mt-4 flex-1 rounded-xl bg-[#f6f8fb] p-3">
            <span
              class="text-[10px] font-bold uppercase tracking-wide text-[#98a2b3]"
              >Ultimo resultado</span
            >
            <p class="mt-1 text-sm font-medium text-[#344054]">
              {{ agent.last_result }}
            </p>
          </div>
          <button
            class="mt-4 inline-flex items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-[#087ff5] to-[#7758e8] px-4 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
            :disabled="agent.status === 'restricted'"
            @click="selectAgent(agent)"
          >
            <i class="i-lucide-sparkles size-4" />
            {{ t('JRC_NICO.SELECT_CONVERSATION') }}
          </button>
        </article>
      </section>

      <section
        class="rounded-2xl border border-[#dfe7f2] bg-white p-5 shadow-sm"
      >
        <div class="flex items-center justify-between">
          <div>
            <h2 class="text-lg font-bold text-[#172033]">
              Fluxo de trabalho da IA
            </h2>
            <p class="text-sm text-[#667085]">
              {{ t('JRC_NICO.CENTRAL_DESCRIPTION') }}
            </p>
          </div>
          <i class="i-lucide-workflow size-6 text-violet-600" />
        </div>
        <div class="mt-5 grid gap-3 md:grid-cols-4">
          <div
            v-for="(step, index) in [
              'Usuario pergunta ao Copiloto',
              'Atendente seleciona o especialista',
              'Agente analisa dados permitidos',
              'Copiloto entrega a proxima acao',
            ]"
            :key="step"
            class="relative rounded-2xl bg-[#f6f8fb] p-4"
          >
            <span
              class="grid size-8 place-content-center rounded-full bg-[#087ff5] text-xs font-bold text-white"
              >{{ index + 1 }}</span
            >
            <p class="mt-3 text-sm font-semibold text-[#344054]">{{ step }}</p>
          </div>
        </div>
      </section>
    </div>
  </main>
</template>
