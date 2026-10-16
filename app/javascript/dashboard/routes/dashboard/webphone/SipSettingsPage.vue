<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import AgentsAPI from 'dashboard/api/agents';
import SipCredentialsAPI from 'dashboard/api/sipCredentials';
import PabxSettingsPanel from './PabxSettingsPanel.vue';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();

const TEXT = Object.freeze({
  kicker: 'CONFIGURAÇÃO',
  title: 'Ramais SIP dos agentes',
  subtitle:
    'Selecione um agente desta conta e cadastre o softphone individual. A senha é criptografada no servidor.',
  restricted: 'Esta área é exclusiva do Super Admin.',
  loading: 'Carregando agentes...',
  loadError: 'Não foi possível carregar os agentes desta conta.',
  agents: 'Agentes desta conta',
  agentCount: 'agente(s)',
  configuredAgents: 'ramais configurados',
  selectAgent: 'Selecione um agente para configurar o softphone.',
  noAgents: 'Nenhum agente encontrado nesta conta.',
  configure: 'Configurar',
  edit: 'Editar',
  active: 'Ativo',
  inactive: 'Inativo',
  agent: 'Agente',
  wss: 'Servidor WSS',
  domain: 'Domínio SIP',
  extension: 'Ramal',
  username: 'Usuário SIP',
  password: 'Senha SIP',
  passwordHint: 'Deixe em branco para preservar a senha atual.',
  enabled: 'Ativar botão Ramal para este agente',
  save: 'Salvar e ativar ramal',
  remove: 'Remover configuração',
  saved: 'Ramal salvo e ativado para o agente.',
  removed: 'Configuração do ramal removida.',
  diagnostic: 'Status da configuração',
  configured: 'Configurado',
  notConfigured: 'Não configurado',
});

const currentUser = useMapGetter('getCurrentUser');
const isSuperAdmin = computed(() => currentUser.value.type === 'SuperAdmin');
const agents = ref([]);
const credentials = ref([]);
const selectedUserId = ref('');
const loading = ref(true);
const saving = ref(false);
const loadError = ref('');

const form = reactive({
  wss_server: 'wss://cloud.jrcpabx.com.br:7443',
  sip_domain: 'cloud.jrcpabx.com.br',
  extension: '',
  call_history_extension: '',
  username: '',
  password: '',
  enabled: true,
});

const selectedAgent = computed(() =>
  agents.value.find(agent => String(agent.id) === String(selectedUserId.value))
);
const selectedCredential = computed(() =>
  credentials.value.find(
    credential => String(credential.user_id) === String(selectedUserId.value)
  )
);
const agentsWithCredentials = computed(() =>
  agents.value.map(agent => ({
    ...agent,
    sipCredential: credentials.value.find(
      credential => String(credential.user_id) === String(agent.id)
    ),
  }))
);
const configuredCount = computed(
  () => credentials.value.filter(credential => credential.configured).length
);

const selectAgent = userId => {
  selectedUserId.value = String(userId);
};

const resetForm = () => {
  const credential = selectedCredential.value;
  form.wss_server = credential?.wss_server || 'wss://cloud.jrcpabx.com.br:7443';
  form.sip_domain = credential?.sip_domain || 'cloud.jrcpabx.com.br';
  form.extension = credential?.extension || '';
  form.call_history_extension =
    credential?.call_history_extension || credential?.extension || '';
  form.username = credential?.username || credential?.extension || '';
  form.password = '';
  form.enabled = credential?.enabled ?? true;
};

watch(selectedUserId, resetForm);
watch(
  () => form.extension,
  (value, previous) => {
    if (!form.username || form.username === previous) form.username = value;
  }
);

const loadData = async () => {
  if (!isSuperAdmin.value) {
    loading.value = false;
    return;
  }
  loadError.value = '';
  try {
    const [{ data: agentData }, { data: credentialData }] = await Promise.all([
      AgentsAPI.get(),
      SipCredentialsAPI.get(),
    ]);
    agents.value = agentData;
    credentials.value = credentialData;
    selectedUserId.value ||= String(agentData[0]?.id || '');
    resetForm();
  } catch {
    loadError.value = TEXT.loadError;
  } finally {
    loading.value = false;
  }
};

const save = async () => {
  if (!selectedUserId.value) return;
  saving.value = true;
  try {
    const { data } = await SipCredentialsAPI.saveForAgent(
      selectedUserId.value,
      form
    );
    const existingIndex = credentials.value.findIndex(
      item => item.user_id === data.user_id
    );
    if (existingIndex >= 0) credentials.value.splice(existingIndex, 1, data);
    else credentials.value.push(data);
    form.password = '';
    useAlert(TEXT.saved);
  } catch (error) {
    useAlert(
      error?.response?.data?.message || 'Não foi possível salvar o ramal.'
    );
  } finally {
    saving.value = false;
  }
};

const remove = async () => {
  if (!selectedUserId.value || !selectedCredential.value) return;
  await SipCredentialsAPI.removeFromAgent(selectedUserId.value);
  credentials.value = credentials.value.filter(
    item => String(item.user_id) !== String(selectedUserId.value)
  );
  resetForm();
  useAlert(TEXT.removed);
};

onMounted(() => loadData());
</script>

<template>
  <section class="h-full w-full overflow-y-auto bg-n-background p-6 lg:p-10">
    <div class="mx-auto max-w-6xl">
      <div
        v-if="!isSuperAdmin"
        class="rounded-3xl border border-n-ruby-7 bg-n-ruby-3 p-8 text-center text-n-ruby-11"
      >
        {{ TEXT.restricted }}
      </div>
      <div v-else>
        <PabxSettingsPanel />
        <header class="mb-6">
          <p class="text-xs font-bold tracking-[0.14em] text-n-teal-11">
            {{ TEXT.kicker }}
          </p>
          <div class="mt-2 flex flex-wrap items-end justify-between gap-3">
            <div>
              <h1 class="text-2xl font-semibold text-n-slate-12">
                {{ TEXT.title }}
              </h1>
              <p class="mt-2 max-w-3xl text-sm leading-6 text-n-slate-10">
                {{ TEXT.subtitle }}
              </p>
            </div>
            <span
              class="rounded-full border border-n-weak bg-n-solid-2 px-4 py-2 text-xs font-semibold text-n-slate-11"
            >
              {{ configuredCount }}/{{ agents.length }}
              {{ TEXT.configuredAgents }}
            </span>
          </div>
        </header>

        <div
          v-if="loading"
          class="rounded-3xl border border-n-weak bg-n-solid-2 p-8 text-n-slate-11"
        >
          {{ TEXT.loading }}
        </div>
        <div
          v-else-if="loadError"
          class="rounded-3xl border border-n-ruby-7 bg-n-ruby-3 p-8 text-center text-n-ruby-11"
        >
          {{ loadError }}
        </div>
        <div v-else class="grid gap-5 lg:grid-cols-[360px_1fr]">
          <aside
            class="overflow-hidden rounded-3xl border border-n-weak bg-n-solid-2 shadow-sm"
          >
            <div class="border-b border-n-weak px-5 py-4">
              <h2 class="font-semibold text-n-slate-12">{{ TEXT.agents }}</h2>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ agents.length }} {{ TEXT.agentCount }}
              </p>
            </div>
            <div
              v-if="!agents.length"
              class="p-6 text-center text-sm text-n-slate-10"
            >
              {{ TEXT.noAgents }}
            </div>
            <div v-else class="max-h-[620px] space-y-2 overflow-y-auto p-3">
              <button
                v-for="agent in agentsWithCredentials"
                :key="agent.id"
                type="button"
                class="group flex w-full items-center gap-3 rounded-2xl border p-3 text-left transition"
                :class="
                  String(agent.id) === selectedUserId
                    ? 'border-n-brand bg-n-brand/10'
                    : 'border-transparent hover:border-n-weak hover:bg-n-alpha-2'
                "
                :aria-pressed="String(agent.id) === selectedUserId"
                @click="selectAgent(agent.id)"
              >
                <span
                  class="flex size-10 shrink-0 items-center justify-center rounded-xl bg-n-alpha-3 text-sm font-bold text-n-slate-12"
                >
                  {{
                    (agent.available_name || agent.email)
                      .slice(0, 2)
                      .toUpperCase()
                  }}
                </span>
                <span class="min-w-0 flex-1">
                  <strong class="block truncate text-sm text-n-slate-12">
                    {{ agent.available_name }}
                  </strong>
                  <span class="block truncate text-xs text-n-slate-10">
                    {{ agent.email }}
                  </span>
                  <span class="mt-1.5 flex items-center gap-2 text-xs">
                    <span
                      class="size-2 rounded-full"
                      :class="
                        agent.sipCredential?.configured
                          ? 'bg-n-teal-9'
                          : agent.sipCredential
                            ? 'bg-n-amber-9'
                            : 'bg-n-slate-7'
                      "
                    />
                    <span class="text-n-slate-11">
                      {{
                        agent.sipCredential?.configured
                          ? TEXT.active
                          : agent.sipCredential
                            ? TEXT.inactive
                            : TEXT.notConfigured
                      }}
                      <template v-if="agent.sipCredential?.extension">
                        · {{ TEXT.extension }}
                        {{ agent.sipCredential.extension }}
                      </template>
                    </span>
                  </span>
                </span>
                <span
                  class="text-xs font-semibold text-n-brand opacity-80 group-hover:opacity-100"
                >
                  {{ agent.sipCredential ? TEXT.edit : TEXT.configure }}
                </span>
              </button>
            </div>
          </aside>

          <form
            v-if="selectedAgent"
            class="rounded-3xl border border-n-weak bg-n-solid-2 p-6 shadow-sm lg:p-8"
            @submit.prevent="save"
          >
            <div
              class="mb-7 flex flex-wrap items-start justify-between gap-4 border-b border-n-weak pb-5"
            >
              <div>
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ selectedAgent.available_name }}
                </p>
                <p class="mt-1 text-sm text-n-slate-10">
                  {{ selectedAgent.email }}
                </p>
              </div>
              <span
                class="rounded-full border px-3 py-1.5 text-xs font-semibold"
                :class="
                  selectedCredential?.configured
                    ? 'border-n-teal-7 bg-n-teal-3 text-n-teal-11'
                    : 'border-n-weak bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{
                  selectedCredential?.configured
                    ? TEXT.active
                    : TEXT.notConfigured
                }}
              </span>
            </div>

            <div class="grid gap-5 sm:grid-cols-2">
              <label class="jrc-field sm:col-span-2">
                <span>{{ TEXT.wss }}</span>
                <input v-model.trim="form.wss_server" required type="url" />
              </label>
              <label class="jrc-field">
                <span>{{ TEXT.domain }}</span>
                <input v-model.trim="form.sip_domain" required />
              </label>
              <label class="jrc-field">
                <span>{{ TEXT.extension }}</span>
                <input
                  v-model.trim="form.extension"
                  required
                  inputmode="numeric"
                />
              </label>
              <label class="jrc-field">
                <span>{{ TEXT.username }}</span>
                <input v-model.trim="form.username" required />
              </label>
              <label class="jrc-field">
                <span>{{ t('SOFTPHONE.PABX.HISTORY_EXTENSION') }}</span>
                <input
                  v-model.trim="form.call_history_extension"
                  inputmode="numeric"
                />
              </label>
              <label class="jrc-field">
                <span>{{ TEXT.password }}</span>
                <input
                  v-model="form.password"
                  type="password"
                  :required="!selectedCredential?.password_configured"
                  autocomplete="new-password"
                />
                <small>{{ TEXT.passwordHint }}</small>
              </label>
              <label class="flex items-center gap-3 sm:col-span-2">
                <input v-model="form.enabled" type="checkbox" class="size-4" />
                <span class="font-medium text-n-slate-12">{{
                  TEXT.enabled
                }}</span>
              </label>
            </div>

            <div class="mt-7 flex flex-wrap gap-3">
              <button
                type="submit"
                class="rounded-xl bg-n-brand px-5 py-3 font-semibold text-white hover:brightness-110 disabled:opacity-50"
                :disabled="saving"
              >
                {{ TEXT.save }}
              </button>
              <button
                v-if="selectedCredential"
                type="button"
                class="rounded-xl border border-n-ruby-7 bg-n-ruby-3 px-5 py-3 font-semibold text-n-ruby-11 hover:brightness-110"
                @click="remove"
              >
                {{ TEXT.remove }}
              </button>
            </div>
          </form>
          <div
            v-else
            class="flex min-h-[360px] items-center justify-center rounded-3xl border border-dashed border-n-strong bg-n-solid-2 p-8 text-center text-n-slate-10"
          >
            {{ TEXT.selectAgent }}
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<style lang="scss" scoped>
.jrc-field {
  @apply grid gap-2 text-sm font-semibold text-n-slate-11;

  input,
  select {
    @apply h-12 w-full rounded-xl border border-n-weak bg-n-alpha-1 px-4 font-normal text-n-slate-12 outline-none focus:border-n-brand;
  }

  small {
    @apply font-normal text-n-slate-10;
  }
}
</style>
