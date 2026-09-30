<script setup>
/* eslint-disable vue/no-bare-strings-in-template, @intlify/vue-i18n/no-raw-text */
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import jrcAiAPI from 'dashboard/api/jrcAi';

const props = defineProps({
  initialTab: { type: String, default: 'providers' },
});
const currentRole = useMapGetter('getCurrentRole');
const { t } = useI18n();
const isAdministrator = computed(() => currentRole.value === 'administrator');
const activeTab = ref(props.initialTab);
const loading = ref(false);
const saving = ref(false);
const providers = ref([]);
const usage = ref({
  totals: {},
  by_agent: [],
  by_model: [],
  by_user: [],
  recent: [],
});
const showForm = ref(false);
const editingId = ref(null);
const error = ref('');

const emptyForm = () => ({
  provider_type: 'openai',
  name: 'JRC OpenAI Producao',
  api_key: '',
  base_url: 'https://api.openai.com',
  default_model: '',
  fast_model: '',
  advanced_model: '',
  monthly_token_limit: '',
  monthly_budget_brl: '',
  active: true,
  default_provider: false,
});
const form = ref(emptyForm());
const providerOptions = [
  { value: 'openai', label: 'OpenAI', compatible: true },
  { value: 'azure_openai', label: 'Azure OpenAI', compatible: true },
  { value: 'google_gemini', label: 'Google Gemini', compatible: false },
  { value: 'anthropic', label: 'Anthropic', compatible: false },
  { value: 'custom', label: 'API compativel com OpenAI', compatible: true },
];
const tabs = [
  { key: 'providers', label: 'Provedores', icon: 'i-lucide-key-round' },
  { key: 'models', label: 'Modelos', icon: 'i-lucide-boxes' },
  { key: 'usage', label: 'Tokens e consumo', icon: 'i-lucide-gauge' },
  { key: 'security', label: 'Seguranca', icon: 'i-lucide-shield-check' },
  { key: 'logs', label: 'Logs', icon: 'i-lucide-scroll-text' },
];

const providerLabel = type =>
  providerOptions.find(item => item.value === type)?.label || type;
const statusLabel = status =>
  ({
    not_validated: 'Nao validado',
    configured: 'Configurado',
    error: 'Erro',
    disabled: 'Desativado',
  })[status] || status;
const statusClass = status =>
  ({
    configured: 'bg-emerald-100 text-emerald-700',
    error: 'bg-rose-100 text-rose-700',
    disabled: 'bg-n-slate-3 text-n-slate-11',
    not_validated: 'bg-amber-100 text-amber-700',
  })[status] || 'bg-n-slate-3 text-n-slate-11';
const formatNumber = value =>
  new Intl.NumberFormat('pt-BR').format(Number(value || 0));
const formatMoney = cents =>
  cents == null
    ? 'Indisponível'
    : new Intl.NumberFormat('pt-BR', {
        style: 'currency',
        currency: 'BRL',
      }).format(Number(cents) / 100);
const formatDate = value =>
  value
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : '--';
const currentProviderType = computed(() =>
  providerOptions.find(item => item.value === form.value.provider_type)
);

const load = async () => {
  if (!isAdministrator.value) return;
  loading.value = true;
  error.value = '';
  try {
    const [providersResponse, usageResponse] = await Promise.all([
      jrcAiAPI.providers(),
      jrcAiAPI.usage(),
    ]);
    providers.value = providersResponse.data;
    usage.value = usageResponse.data;
  } catch (requestError) {
    error.value =
      requestError?.response?.data?.error ||
      'Nao foi possivel carregar as configuracoes de IA.';
  } finally {
    loading.value = false;
  }
};

const startCreate = () => {
  editingId.value = null;
  form.value = emptyForm();
  showForm.value = true;
};
const startEdit = provider => {
  editingId.value = provider.id;
  form.value = {
    provider_type: provider.provider_type,
    name: provider.name,
    api_key: '',
    base_url: provider.base_url || '',
    default_model: provider.default_model || '',
    fast_model: provider.fast_model || '',
    advanced_model: provider.advanced_model || '',
    monthly_token_limit: provider.monthly_token_limit || '',
    monthly_budget_brl: provider.monthly_budget_cents
      ? provider.monthly_budget_cents / 100
      : '',
    active: provider.active,
    default_provider: provider.default_provider,
  };
  showForm.value = true;
};
const providerChanged = () => {
  if (form.value.provider_type === 'openai' && !form.value.base_url) {
    form.value.base_url = 'https://api.openai.com';
  }
};
const buildPayload = () => ({
  provider_type: form.value.provider_type,
  name: form.value.name.trim(),
  api_key: form.value.api_key,
  base_url: form.value.base_url.trim(),
  default_model: form.value.default_model.trim(),
  fast_model: form.value.fast_model.trim(),
  advanced_model: form.value.advanced_model.trim(),
  monthly_token_limit:
    form.value.monthly_token_limit === ''
      ? null
      : Number(form.value.monthly_token_limit),
  monthly_budget_cents:
    form.value.monthly_budget_brl === ''
      ? null
      : Math.round(Number(form.value.monthly_budget_brl) * 100),
  active: form.value.active,
  default_provider: form.value.default_provider,
});
const save = async () => {
  if (!form.value.name.trim() || !form.value.default_model.trim()) {
    useAlert('Informe o nome da conexao e o modelo padrao.');
    return;
  }
  if (!editingId.value && !form.value.api_key.trim()) {
    useAlert(t('JRC_NICO.PROVIDER.API_KEY_REQUIRED'));
    return;
  }
  saving.value = true;
  try {
    const payload = buildPayload();
    if (editingId.value)
      await jrcAiAPI.updateProvider(editingId.value, payload);
    else await jrcAiAPI.createProvider(payload);
    useAlert('Configuracao de IA salva com sucesso.');
    showForm.value = false;
    await load();
  } catch (requestError) {
    const messages = requestError?.response?.data?.errors;
    useAlert(
      Array.isArray(messages)
        ? messages.join(', ')
        : 'Nao foi possivel salvar o provedor.'
    );
  } finally {
    saving.value = false;
  }
};
const validateProvider = async provider => {
  try {
    const response = await jrcAiAPI.validateProvider(provider.id);
    useAlert(response.data.message || 'Configuracao validada.');
    await load();
  } catch (requestError) {
    useAlert(
      requestError?.response?.data?.message ||
        'A configuracao possui pendencias.'
    );
    await load();
  }
};
const makeDefault = async provider => {
  if (saving.value || !isAdministrator.value) return;
  saving.value = true;
  try {
    await jrcAiAPI.makeDefault(provider.id);
    useAlert('Provedor padrao atualizado.');
    await load();
  } catch {
    useAlert(t('JRC_NICO.OPERATOR.ACTION_ERROR'));
  } finally {
    saving.value = false;
  }
};
const removeProvider = async provider => {
  if (saving.value || !isAdministrator.value) return;
  if (!window.confirm(`Excluir a conexao ${provider.name}?`)) return;
  saving.value = true;
  try {
    await jrcAiAPI.deleteProvider(provider.id);
    useAlert('Provedor removido.');
    await load();
  } catch {
    useAlert(t('JRC_NICO.OPERATOR.ACTION_ERROR'));
  } finally {
    saving.value = false;
  }
};

watch(
  () => props.initialTab,
  value => {
    activeTab.value = value;
  }
);
onMounted(load);
</script>

<template>
  <main class="h-full overflow-auto bg-n-surface-1 p-4 sm:p-5">
    <div class="mx-auto max-w-[1500px] space-y-4">
      <header
        class="rounded-3xl bg-gradient-to-r from-[#062f57] via-[#075a87] to-[#7758e8] p-6 text-white shadow-lg"
      >
        <span
          class="inline-flex items-center gap-2 rounded-full bg-white/10 px-3 py-1 text-[11px] font-bold uppercase"
          ><i class="i-lucide-shield-check size-4" /> Administracao</span
        >
        <h1 class="mt-3 text-3xl font-bold text-inherit">
          Intelig&ecirc;ncia Artificial
        </h1>
        <p class="mt-2 max-w-3xl text-sm text-blue-50/90">
          Cadastre provedores, modelos e limites de consumo. A chave nunca
          &eacute; devolvida ao navegador depois de salva e as chamadas do
          Copiloto passam pelo backend.
        </p>
      </header>

      <section
        v-if="!isAdministrator"
        class="rounded-2xl border border-amber-200 bg-amber-50 p-6"
      >
        <div class="flex gap-3">
          <i class="i-lucide-lock-keyhole size-6 text-amber-700" />
          <div>
            <h2 class="font-bold text-amber-900">
              Acesso administrativo necess&aacute;rio
            </h2>
            <p class="mt-1 text-sm text-amber-800">
              Somente administradores podem cadastrar tokens, modelos e limites
              financeiros.
            </p>
          </div>
        </div>
      </section>

      <template v-else>
        <nav
          class="flex gap-2 overflow-x-auto rounded-2xl border border-n-weak bg-n-solid-2 p-2 shadow-sm"
        >
          <button
            v-for="tab in tabs"
            :key="tab.key"
            class="inline-flex shrink-0 items-center gap-2 rounded-xl px-4 py-2.5 text-sm font-semibold transition"
            :class="
              activeTab === tab.key
                ? 'bg-n-brand text-white shadow'
                : 'text-n-slate-11 hover:bg-n-slate-2'
            "
            @click="activeTab = tab.key"
          >
            <i class="size-4" :class="tab.icon" />{{ tab.label }}
          </button>
        </nav>
        <div
          v-if="error"
          class="rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700"
        >
          {{ error }}
        </div>

        <section v-if="activeTab === 'providers'" class="space-y-4">
          <div
            class="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
          >
            <div>
              <h2 class="font-bold text-n-slate-12">Provedores configurados</h2>
              <p class="text-xs text-n-slate-11">
                OpenAI e APIs compat&iacute;veis podem alimentar o Copiloto
                nesta vers&atilde;o. Outros provedores ficam cadastrados para
                adaptadores futuros.
              </p>
            </div>
            <button
              class="inline-flex items-center gap-2 rounded-xl bg-n-brand hover:enabled:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand px-4 py-2.5 text-sm font-semibold text-white"
              @click="startCreate"
            >
              <i class="i-lucide-plus size-4" /> Novo provedor
            </button>
          </div>
          <div class="grid gap-4 lg:grid-cols-2">
            <article
              v-for="provider in providers"
              :key="provider.id"
              class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
            >
              <div class="flex items-start justify-between gap-3">
                <div class="flex gap-3">
                  <span
                    class="grid size-11 place-content-center rounded-xl bg-gradient-to-br from-blue-50 to-violet-100 text-blue-700"
                    ><i class="i-lucide-key-round size-5"
                  /></span>
                  <div>
                    <div class="flex flex-wrap items-center gap-2">
                      <h3 class="font-bold text-n-slate-12">
                        {{ provider.name }}
                      </h3>
                      <span
                        v-if="provider.default_provider"
                        class="rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-bold text-blue-700"
                        >PADRAO</span
                      >
                    </div>
                    <p class="text-xs text-n-slate-11">
                      {{ providerLabel(provider.provider_type) }} &middot;
                      {{ provider.default_model || 'Sem modelo' }}
                    </p>
                  </div>
                </div>
                <span
                  class="rounded-full px-2.5 py-1 text-[10px] font-bold uppercase"
                  :class="statusClass(provider.status)"
                  >{{ statusLabel(provider.status) }}</span
                >
              </div>
              <dl
                class="mt-5 grid grid-cols-2 gap-3 rounded-xl bg-n-surface-1 p-4 text-xs"
              >
                <div>
                  <dt class="text-n-slate-11">
                    {{ t('JRC_NICO.PROVIDER.API_KEY') }}
                  </dt>
                  <dd class="mt-1 font-semibold text-n-slate-12">
                    {{ provider.masked_api_key || 'Nao cadastrada' }}
                  </dd>
                </div>
                <div>
                  <dt class="text-n-slate-11">Compatibilidade</dt>
                  <dd
                    class="mt-1 font-semibold"
                    :class="
                      provider.openai_compatible
                        ? 'text-emerald-700'
                        : 'text-amber-700'
                    "
                  >
                    {{
                      provider.openai_compatible
                        ? 'Copiloto habilitado'
                        : 'Adaptador pendente'
                    }}
                  </dd>
                </div>
                <div>
                  <dt class="text-n-slate-11">Limite mensal</dt>
                  <dd class="mt-1 font-semibold text-n-slate-12">
                    {{
                      provider.monthly_token_limit
                        ? formatNumber(provider.monthly_token_limit) + ' tokens'
                        : 'Sem limite'
                    }}
                  </dd>
                </div>
                <div>
                  <dt class="text-n-slate-11">Orcamento mensal</dt>
                  <dd class="mt-1 font-semibold text-n-slate-12">
                    {{
                      provider.monthly_budget_cents
                        ? formatMoney(provider.monthly_budget_cents)
                        : 'Sem limite'
                    }}
                  </dd>
                </div>
              </dl>
              <p
                v-if="provider.last_error"
                class="mt-3 rounded-xl bg-rose-50 p-3 text-xs text-rose-700"
              >
                {{ provider.last_error }}
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <button
                  class="rounded-xl border border-blue-200 px-3 py-2 text-xs font-semibold text-blue-700"
                  @click="startEdit(provider)"
                >
                  Editar</button
                ><button
                  class="rounded-xl border border-emerald-200 px-3 py-2 text-xs font-semibold text-emerald-700"
                  @click="validateProvider(provider)"
                >
                  Validar configura&ccedil;&atilde;o</button
                ><button
                  v-if="!provider.default_provider"
                  class="rounded-xl border border-violet-200 px-3 py-2 text-xs font-semibold text-violet-700"
                  @click="makeDefault(provider)"
                >
                  Definir como padr&atilde;o</button
                ><button
                  class="ml-auto rounded-xl border border-rose-200 px-3 py-2 text-xs font-semibold text-rose-700"
                  @click="removeProvider(provider)"
                >
                  Excluir
                </button>
              </div>
            </article>
            <button
              v-if="!providers.length && !loading"
              class="rounded-2xl border-2 border-dashed border-blue-200 bg-blue-50/50 p-10 text-center"
              @click="startCreate"
            >
              <i class="i-lucide-key-round mx-auto size-8 text-blue-600" /><b
                class="mt-3 block text-n-slate-12"
                >Nenhum provedor configurado</b
              ><span class="mt-1 block text-sm text-n-slate-11"
                >Cadastre a primeira conex&atilde;o para ativar respostas de
                IA.</span
              >
            </button>
          </div>
        </section>

        <section
          v-else-if="activeTab === 'models'"
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <h2 class="text-lg font-bold text-n-slate-12">
            Modelos por provedor
          </h2>
          <p class="text-sm text-n-slate-11">
            Separe um modelo r&aacute;pido, um padr&atilde;o e um
            avan&ccedil;ado conforme custo e complexidade.
          </p>
          <div class="mt-5 overflow-x-auto">
            <table class="w-full min-w-[800px] text-left text-sm">
              <thead
                class="border-b border-n-weak text-xs uppercase text-n-slate-11"
              >
                <tr>
                  <th class="p-3">Conexao</th>
                  <th class="p-3">Modelo rapido</th>
                  <th class="p-3">Modelo padrao</th>
                  <th class="p-3">Modelo avancado</th>
                  <th class="p-3">Status</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="provider in providers"
                  :key="provider.id"
                  class="border-b border-slate-100"
                >
                  <td class="p-3 font-semibold text-n-slate-12">
                    {{ provider.name }}
                  </td>
                  <td class="p-3 text-n-slate-11">
                    {{ provider.fast_model || '--' }}
                  </td>
                  <td class="p-3 text-n-slate-11">
                    {{ provider.default_model || '--' }}
                  </td>
                  <td class="p-3 text-n-slate-11">
                    {{ provider.advanced_model || '--' }}
                  </td>
                  <td class="p-3">
                    <span
                      class="rounded-full px-2 py-1 text-[10px] font-bold"
                      :class="statusClass(provider.status)"
                      >{{ statusLabel(provider.status) }}</span
                    >
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section v-else-if="activeTab === 'usage'" class="space-y-4">
          <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
            <article
              v-for="card in [
                {
                  label: 'Tokens hoje',
                  value: formatNumber(usage.totals.tokens_today),
                },
                {
                  label: 'Tokens no mes',
                  value: formatNumber(usage.totals.total_tokens),
                },
                {
                  label: 'Execucoes',
                  value: formatNumber(usage.totals.executions),
                },
                {
                  label: 'Entrada',
                  value: formatNumber(usage.totals.input_tokens),
                },
                {
                  label: 'Custo estimado',
                  value: formatMoney(usage.totals.estimated_cost_cents),
                },
              ]"
              :key="card.label"
              class="rounded-2xl border border-n-weak bg-n-solid-2 p-4 shadow-sm"
            >
              <p class="text-xs text-n-slate-11">{{ card.label }}</p>
              <strong class="mt-2 block text-2xl text-n-slate-12">{{
                card.value
              }}</strong>
            </article>
          </div>
          <div class="grid gap-4 xl:grid-cols-2">
            <article
              class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
            >
              <h2 class="font-bold text-n-slate-12">Consumo por agente</h2>
              <div class="mt-4 space-y-3">
                <div v-for="item in usage.by_agent" :key="item.key">
                  <div class="flex justify-between text-xs">
                    <span class="text-n-slate-11">{{ item.key }}</span
                    ><b class="text-n-slate-12">{{
                      formatNumber(item.tokens)
                    }}</b>
                  </div>
                  <div class="mt-1 h-2 rounded-full bg-n-slate-3">
                    <div
                      class="h-2 rounded-full bg-violet-500"
                      :style="{
                        width: `${Math.min(100, (item.tokens / Math.max(1, usage.totals.total_tokens)) * 100)}%`,
                      }"
                    />
                  </div>
                </div>
                <p
                  v-if="!usage.by_agent.length"
                  class="text-sm text-n-slate-11"
                >
                  O consumo aparecer&aacute; depois das primeiras chamadas de
                  IA.
                </p>
              </div>
            </article>
            <article
              class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
            >
              <h2 class="font-bold text-n-slate-12">
                Consumo por usu&aacute;rio
              </h2>
              <div class="mt-4 space-y-3">
                <div
                  v-for="item in usage.by_user"
                  :key="item.key"
                  class="flex items-center justify-between rounded-xl bg-n-surface-1 p-3"
                >
                  <span class="text-sm text-n-slate-12">{{ item.label }}</span
                  ><b class="text-sm text-n-slate-12"
                    >{{ formatNumber(item.tokens) }} tokens</b
                  >
                </div>
                <p v-if="!usage.by_user.length" class="text-sm text-n-slate-11">
                  Nenhum consumo registrado neste m&ecirc;s.
                </p>
              </div>
            </article>
          </div>
        </section>

        <section
          v-else-if="activeTab === 'security'"
          class="grid gap-4 xl:grid-cols-2"
        >
          <article
            class="rounded-2xl border border-emerald-200 bg-n-solid-2 p-5 shadow-sm"
          >
            <span
              class="grid size-11 place-content-center rounded-xl bg-emerald-50 text-emerald-700"
              ><i class="i-lucide-lock-keyhole size-5"
            /></span>
            <h2 class="mt-4 font-bold text-n-slate-12">
              Prote&ccedil;&atilde;o das chaves
            </h2>
            <ul class="mt-3 space-y-2 text-sm leading-6 text-n-slate-11">
              <li>A chave fica criptografada no banco pelo backend Rails.</li>
              <li>A API retorna apenas uma vers&atilde;o mascarada.</li>
              <li>
                O navegador nunca recebe a chave completa depois de salva.
              </li>
              <li>Somente administradores acessam esta tela.</li>
            </ul>
          </article>
          <article
            class="rounded-2xl border border-blue-200 bg-n-solid-2 p-5 shadow-sm"
          >
            <span
              class="grid size-11 place-content-center rounded-xl bg-blue-50 text-blue-700"
              ><i class="i-lucide-server-cog size-5"
            /></span>
            <h2 class="mt-4 font-bold text-n-slate-12">Fluxo seguro</h2>
            <ol class="mt-3 space-y-2 text-sm leading-6 text-n-slate-11">
              <li>1. O usu&aacute;rio envia a pergunta ao backend.</li>
              <li>2. O backend aplica permiss&otilde;es e contexto.</li>
              <li>3. O backend usa a credencial criptografada.</li>
              <li>
                4. Tokens e execu&ccedil;&atilde;o s&atilde;o registrados para
                auditoria.
              </li>
            </ol>
          </article>
        </section>

        <section
          v-else
          class="rounded-2xl border border-n-weak bg-n-solid-2 p-5 shadow-sm"
        >
          <div class="flex items-center justify-between">
            <div>
              <h2 class="text-lg font-bold text-n-slate-12">
                Logs de uso de IA
              </h2>
              <p class="text-sm text-n-slate-11">
                Somente metadados de consumo; a chave da API nunca &eacute;
                registrada.
              </p>
            </div>
            <button
              class="grid size-9 place-content-center rounded-xl bg-blue-50 text-blue-700"
              @click="load"
            >
              <i class="i-lucide-refresh-cw size-4" />
            </button>
          </div>
          <div class="mt-5 overflow-x-auto">
            <table class="w-full min-w-[900px] text-left text-sm">
              <thead
                class="border-b border-n-weak text-xs uppercase text-n-slate-11"
              >
                <tr>
                  <th class="p-3">Data</th>
                  <th class="p-3">Agente</th>
                  <th class="p-3">Modelo</th>
                  <th class="p-3">Entrada</th>
                  <th class="p-3">Saida</th>
                  <th class="p-3">Total</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="event in usage.recent"
                  :key="event.id"
                  class="border-b border-slate-100"
                >
                  <td class="p-3 text-n-slate-11">
                    {{ formatDate(event.created_at) }}
                  </td>
                  <td class="p-3 font-semibold text-n-slate-12">
                    {{ event.agent_key }}
                  </td>
                  <td class="p-3 text-n-slate-11">{{ event.model || '--' }}</td>
                  <td class="p-3 text-n-slate-11">
                    {{ formatNumber(event.input_tokens) }}
                  </td>
                  <td class="p-3 text-n-slate-11">
                    {{ formatNumber(event.output_tokens) }}
                  </td>
                  <td class="p-3 font-semibold text-n-slate-12">
                    {{ formatNumber(event.total_tokens) }}
                  </td>
                </tr>
              </tbody>
            </table>
            <p
              v-if="!usage.recent.length"
              class="p-6 text-center text-sm text-n-slate-11"
            >
              Nenhuma execu&ccedil;&atilde;o registrada.
            </p>
          </div>
        </section>
      </template>

      <div
        v-if="showForm"
        class="fixed inset-0 z-[90] flex items-start justify-center overflow-y-auto bg-slate-950/50 p-4"
        @click.self="showForm = false"
      >
        <form
          class="my-auto max-h-[calc(100dvh-2rem)] w-full max-w-3xl overflow-y-auto overscroll-contain rounded-3xl bg-n-solid-2 p-6 shadow-2xl"
          @submit.prevent="save"
        >
          <div class="flex items-center justify-between">
            <div>
              <h2 class="text-xl font-bold text-n-slate-12">
                {{ editingId ? 'Editar provedor' : 'Novo provedor de IA' }}
              </h2>
              <p class="text-sm text-n-slate-11">
                A chave ser&aacute; enviada uma vez ao backend e armazenada de
                forma criptografada.
              </p>
            </div>
            <button
              type="button"
              class="grid size-9 place-content-center rounded-xl bg-n-slate-3"
              :aria-label="t('GENERAL.CLOSE')"
              @click="showForm = false"
            >
              <i class="i-lucide-x size-4" />
            </button>
          </div>
          <div class="mt-6 grid gap-4 md:grid-cols-2">
            <label class="text-sm font-medium text-n-slate-12"
              >Provedor<select
                v-model="form.provider_type"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 outline-none focus:border-blue-500"
                @change="providerChanged"
              >
                <option
                  v-for="option in providerOptions"
                  :key="option.value"
                  :value="option.value"
                >
                  {{ option.label }}
                </option>
              </select></label
            ><label class="text-sm font-medium text-n-slate-12"
              >Nome da conex&atilde;o<input
                v-model="form.name"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 outline-none focus:border-blue-500"
                placeholder="JRC IA Producao" /></label
            ><label class="md:col-span-2 text-sm font-medium text-n-slate-12"
              >{{ t('JRC_NICO.PROVIDER.API_KEY')
              }}<input
                v-model="form.api_key"
                type="password"
                autocomplete="new-password"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 font-mono outline-none focus:border-blue-500"
                :placeholder="
                  editingId
                    ? 'Deixe vazio para manter a chave atual'
                    : 'Cole a chave do provedor'
                " /></label
            ><label class="md:col-span-2 text-sm font-medium text-n-slate-12"
              >URL base<input
                v-model="form.base_url"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 font-mono text-xs outline-none focus:border-blue-500"
                placeholder="https://api.exemplo.com" /></label
            ><label class="text-sm font-medium text-n-slate-12"
              >Modelo r&aacute;pido<input
                v-model="form.fast_model"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 outline-none focus:border-blue-500"
                placeholder="Nome do modelo" /></label
            ><label class="text-sm font-medium text-n-slate-12"
              >Modelo padr&atilde;o *<input
                v-model="form.default_model"
                required
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 outline-none focus:border-blue-500"
                placeholder="Nome do modelo" /></label
            ><label class="text-sm font-medium text-n-slate-12"
              >Modelo avan&ccedil;ado<input
                v-model="form.advanced_model"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 outline-none focus:border-blue-500"
                placeholder="Nome do modelo" /></label
            ><label class="text-sm font-medium text-n-slate-12"
              >Limite mensal de tokens<input
                v-model="form.monthly_token_limit"
                type="number"
                min="0"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 outline-none focus:border-blue-500"
                placeholder="Ex.: 1000000" /></label
            ><label class="text-sm font-medium text-n-slate-12"
              >Limite financeiro mensal (R$)<input
                v-model="form.monthly_budget_brl"
                type="number"
                min="0"
                step="0.01"
                class="mt-1 h-11 w-full rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 outline-none focus:border-blue-500"
                placeholder="Ex.: 500,00"
            /></label>
            <div class="flex flex-wrap items-center gap-5 md:col-span-2">
              <label class="flex items-center gap-2 text-sm text-n-slate-12"
                ><input
                  v-model="form.active"
                  type="checkbox"
                  class="size-4 accent-blue-600"
                />
                Conex&atilde;o ativa</label
              ><label class="flex items-center gap-2 text-sm text-n-slate-12"
                ><input
                  v-model="form.default_provider"
                  type="checkbox"
                  class="size-4 accent-blue-600"
                />
                Provedor padr&atilde;o</label
              >
            </div>
          </div>
          <div
            v-if="!currentProviderType?.compatible"
            class="mt-4 rounded-xl border border-amber-200 bg-amber-50 p-3 text-xs text-amber-800"
          >
            O token ser&aacute; armazenado, mas esta vers&atilde;o ainda precisa
            de um adaptador espec&iacute;fico para usar este provedor no
            Copiloto.
          </div>
          <div class="mt-6 flex justify-end gap-2">
            <button
              type="button"
              class="rounded-xl border border-n-weak px-4 py-2.5 text-sm font-semibold text-n-slate-11"
              @click="showForm = false"
            >
              Cancelar</button
            ><button
              type="submit"
              :disabled="saving"
              class="inline-flex items-center gap-2 rounded-xl bg-n-brand hover:enabled:brightness-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand px-5 py-2.5 text-sm font-semibold text-white disabled:opacity-100 disabled:bg-n-slate-3 disabled:text-n-slate-11 disabled:cursor-not-allowed"
            >
              <i
                v-if="saving"
                class="i-lucide-loader-circle size-4 animate-spin"
              />
              Salvar provedor
            </button>
          </div>
        </form>
      </div>
    </div>
  </main>
</template>
