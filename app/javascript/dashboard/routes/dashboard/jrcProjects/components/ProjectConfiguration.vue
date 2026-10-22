<script setup>
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import CompanyPicker from 'dashboard/routes/dashboard/jrcCustomers/components/CompanyPicker.vue';
import { useCustomerMaster } from 'dashboard/routes/dashboard/jrcCustomers/useCustomerMaster';
import { useProjects } from '../useProjects';
import {
  priorityTone,
  statusTone,
  initials,
  useProjectPreferences,
} from '../projectPresentation';
import { projectTaskStatuses } from '../taskBoard';
import { errorMessage, formatDate, request } from '../../jrcOperations/api';
import ContactPicker from '../../jrcOperations/components/ContactPicker.vue';
import ResourceManager from '../../jrcOperations/components/ResourceManager.vue';

const props = defineProps({ project: { type: Object, required: true } });
const emit = defineEmits(['changed']);
const { accountId, userId, projectText } = useProjects();
const {
  enabled: hasCustomerMaster,
  canAccess: canAccessCustomerMaster,
  accountScopedRoute: masterRoute,
} = useCustomerMaster();
const preferences = useProjectPreferences(
  computed(
    () =>
      `jrc:projects:configuration:${accountId.value}:${userId.value}:${props.project.id}`
  ),
  { tab: 'general' }
);
const busy = ref(false);
const error = ref('');
const success = ref('');
const optionsLoading = ref(false);
const optionsError = ref('');
const ownerOptions = ref([]);
const version = ref(null);
const baseline = ref({});
const form = reactive({
  name: '',
  description: '',
  status: '',
  priority: 'medium',
  visibility: 'members',
  company_id: null,
  contact_id: null,
  owner_id: null,
  starts_on: '',
  due_on: '',
  acceptance_notes: '',
});
const canEdit = computed(() =>
  props.project.capabilities?.includes('projects.project.update')
);
const dirty = computed(() =>
  Object.keys(form).some(key => form[key] !== baseline.value[key])
);
const canTransfer = computed(() =>
  props.project.capabilities?.includes('projects.project.transfer')
);
const openProject = computed(
  () => !['completed', 'canceled'].includes(props.project.status)
);
const canManageBoard = computed(
  () =>
    openProject.value &&
    props.project.capabilities?.includes('projects.board.manage')
);
const companyAvailable = computed(
  () => hasCustomerMaster.value && canAccessCustomerMaster.value
);
const pendingTasks = computed(() =>
  Object.entries(props.project.overview?.status_counts || {})
    .filter(([status]) => !['completed', 'canceled'].includes(status))
    .reduce((sum, [, count]) => sum + Number(count), 0)
);
const canComplete = computed(
  () =>
    canEdit.value &&
    openProject.value &&
    pendingTasks.value === 0 &&
    Boolean(form.acceptance_notes.trim())
);
const statusLabels = computed(() => ({
  planned: projectText('CONFIG_STATUS_PLANNED', 'Planejado'),
  active: projectText('CONFIG_STATUS_ACTIVE', 'Em andamento'),
  on_hold: projectText('CONFIG_STATUS_PAUSED', 'Pausado'),
  completed: projectText('CONFIG_STATUS_COMPLETED', 'Concluído'),
  canceled: projectText('CONFIG_STATUS_CANCELED', 'Cancelado'),
}));
const priorityLabels = computed(() => ({
  low: projectText('CONFIG_PRIORITY_LOW', 'Baixa'),
  medium: projectText('CONFIG_PRIORITY_MEDIUM', 'Média'),
  high: projectText('CONFIG_PRIORITY_HIGH', 'Alta'),
  urgent: projectText('CONFIG_PRIORITY_URGENT', 'Urgente'),
}));
const tabs = computed(() => [
  {
    key: 'general',
    label: projectText('CONFIG_GENERAL', 'Dados gerais'),
    icon: 'i-lucide-file-text',
  },
  {
    key: 'scope',
    label: projectText('CONFIG_SCOPE', 'Escopo'),
    icon: 'i-lucide-target',
  },
  {
    key: 'acceptance',
    label: projectText('CONFIG_ACCEPTANCE', 'Aceite e homologação'),
    icon: 'i-lucide-badge-check',
  },
  {
    key: 'board',
    label: projectText('CONFIG_BOARD', 'Configuração do quadro'),
    icon: 'i-lucide-settings',
  },
]);
const tab = computed({
  get: () =>
    tabs.value.some(item => item.key === preferences.tab)
      ? preferences.tab
      : 'general',
  set: value => {
    preferences.tab = value;
  },
});
const columnSchema = computed(() => ({
  key: 'columns',
  title: projectText('CONFIG_COLUMNS', 'Colunas do quadro'),
  help: projectText(
    'CONFIG_COLUMNS_HELP',
    'Organize as colunas, seus estados e limites de tarefas em andamento. Colunas em uso têm proteção contra alterações incompatíveis.'
  ),
  fields: [
    {
      key: 'name',
      label: projectText('CONFIG_NAME', 'Nome'),
      type: 'text',
      required: true,
    },
    {
      key: 'status_key',
      label: projectText('TASK_STATUS', 'Situação das tarefas'),
      type: 'select',
      required: true,
      choices: projectTaskStatuses,
    },
    {
      key: 'position',
      label: projectText('CONFIG_ORDER', 'Ordem'),
      type: 'number',
      min: 0,
      default: props.project.columns?.length || 0,
    },
    {
      key: 'wip_limit',
      label: projectText(
        'CONFIG_WIP_LIMIT',
        'Limite de tarefas (vazio = sem limite)'
      ),
      type: 'number',
      min: 1,
      default: '',
    },
  ],
}));
const projectEvents = computed(() =>
  (props.project.recent_activity || [])
    .filter(event =>
      ['projects.project.created', 'projects.project.updated'].includes(
        event.action
      )
    )
    .slice(0, 5)
);
const controlClass =
  'w-full rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2.5 text-sm text-n-slate-12 outline-none focus:border-n-blue-8 focus:ring-2 focus:ring-n-blue-3 disabled:cursor-not-allowed disabled:bg-n-slate-2 disabled:text-n-slate-11';
const buttonClass =
  'inline-flex items-center justify-center gap-2 rounded-lg border border-n-weak bg-n-solid-1 px-4 py-2.5 text-sm font-medium text-n-slate-12 hover:bg-n-slate-2 disabled:cursor-not-allowed disabled:opacity-60';
const primaryClass =
  'inline-flex items-center justify-center gap-2 rounded-lg bg-n-blue-9 px-4 py-2.5 text-sm font-medium text-white hover:bg-n-blue-10 disabled:cursor-not-allowed disabled:opacity-60';
let optionsGeneration = 0;
let saveGeneration = 0;

function resetDraft(
  record = props.project,
  { preserveDirty = false, savedKeys = [] } = {}
) {
  const next = {};
  Object.keys(form).forEach(key => {
    next[key] = record[key] ?? (key.endsWith('_id') ? null : '');
    if (
      !preserveDirty ||
      form[key] === baseline.value[key] ||
      savedKeys.includes(key)
    )
      form[key] = next[key];
  });
  baseline.value = next;
  version.value = record.lock_version;
}

watch(
  () => [accountId.value, props.project.id, props.project.lock_version],
  (context, previous) => {
    if (!previous || context[0] !== previous[0] || context[1] !== previous[1]) {
      saveGeneration += 1;
      busy.value = false;
      resetDraft();
      error.value = '';
      success.value = '';
    } else if (dirty.value && props.project.lock_version !== version.value) {
      error.value = projectText(
        'CONFIG_CHANGED_ELSEWHERE',
        'O projeto foi atualizado durante a edição. Suas alterações foram mantidas; revise os dados antes de salvar ou descarte o rascunho para carregar a versão atual.'
      );
    } else {
      resetDraft(props.project, { preserveDirty: true });
    }
  },
  { immediate: true }
);

async function loadOwners() {
  optionsGeneration += 1;
  const current = optionsGeneration;
  ownerOptions.value = props.project.owner ? [props.project.owner] : [];
  optionsError.value = '';
  optionsLoading.value = false;
  if (!canTransfer.value) return;
  optionsLoading.value = true;
  try {
    const result = await request(accountId.value, 'operations/options');
    if (current === optionsGeneration) ownerOptions.value = result.data.users;
  } catch (err) {
    if (current === optionsGeneration) optionsError.value = errorMessage(err);
  } finally {
    if (current === optionsGeneration) optionsLoading.value = false;
  }
}

watch(
  () => [accountId.value, props.project.id, canTransfer.value],
  loadOwners,
  { immediate: true }
);

function discard() {
  resetDraft();
  error.value = '';
  success.value = '';
}

function tabKey(event, index) {
  const next = {
    ArrowRight: (index + 1) % tabs.value.length,
    ArrowLeft: (index + tabs.value.length - 1) % tabs.value.length,
    Home: 0,
    End: tabs.value.length - 1,
  }[event.key];
  if (next === undefined) return;
  event.preventDefault();
  tab.value = tabs.value[next].key;
  event.currentTarget.parentElement
    .querySelectorAll('[role="tab"]')
    [next].focus();
}

async function save(section, complete = false) {
  if (busy.value || !canEdit.value) return;
  error.value = '';
  success.value = '';
  if (complete && !canComplete.value) {
    error.value = projectText(
      'CONFIG_COMPLETE_BLOCKED',
      'Conclua ou cancele as tarefas pendentes e registre o aceite antes de encerrar o projeto.'
    );
    return;
  }
  if (
    complete &&
    !window.confirm(
      projectText(
        'CONFIG_COMPLETE_CONFIRM',
        'Registrar este aceite e concluir o projeto? Os registros vinculados continuarão com suas próprias situações.'
      )
    )
  )
    return;
  saveGeneration += 1;
  const current = saveGeneration;
  const values = { lock_version: version.value };
  if (section === 'general') {
    ['name', 'status', 'priority', 'visibility', 'starts_on', 'due_on'].forEach(
      key => {
        values[key] = form[key];
      }
    );
    if (!props.project.contact_locked)
      values.contact_id = form.contact_id || null;
    if (companyAvailable.value) values.company_id = form.company_id || null;
    if (canTransfer.value) values.owner_id = form.owner_id;
  } else if (section === 'scope') {
    values.description = form.description;
  } else {
    values.acceptance_notes = form.acceptance_notes;
    if (complete) values.status = 'completed';
  }
  busy.value = true;
  try {
    const result = await request(
      accountId.value,
      `projects/projects/${props.project.id}`,
      { method: 'patch', data: { project: values } }
    );
    if (current !== saveGeneration) return;
    resetDraft(result.data, {
      preserveDirty: true,
      savedKeys: Object.keys(values),
    });
    success.value = complete
      ? projectText(
          'CONFIG_COMPLETED',
          'Aceite registrado e projeto concluído.'
        )
      : projectText('CONFIG_SAVED', 'Alterações salvas com sucesso.');
    emit('changed');
  } catch (err) {
    if (current === saveGeneration) error.value = errorMessage(err);
  } finally {
    if (current === saveGeneration) busy.value = false;
  }
}

onBeforeUnmount(() => {
  optionsGeneration += 1;
  saveGeneration += 1;
});
</script>

<template>
  <section
    class="overflow-hidden rounded-xl border border-n-weak bg-n-solid-1 shadow-sm"
  >
    <nav
      class="flex gap-2 overflow-x-auto border-b border-n-weak px-4"
      role="tablist"
      :aria-label="projectText('CONFIG_TITLE', 'Projeto e aceite')"
    >
      <button
        v-for="(item, index) in tabs"
        :id="`project-config-tab-${item.key}`"
        :key="item.key"
        class="inline-flex shrink-0 items-center gap-2 border-b-2 px-3 py-4 text-sm font-medium transition-colors"
        :class="
          tab === item.key
            ? 'border-n-blue-9 text-n-blue-11'
            : 'border-transparent text-n-slate-11 hover:text-n-slate-12'
        "
        role="tab"
        type="button"
        :aria-selected="tab === item.key"
        :aria-controls="`project-config-${item.key}`"
        :tabindex="tab === item.key ? 0 : -1"
        :disabled="busy"
        @click="tab = item.key"
        @keydown="tabKey($event, index)"
      >
        <span :class="item.icon" class="h-4 w-4" aria-hidden="true" />{{
          item.label
        }}
      </button>
    </nav>
    <div class="p-4 md:p-5">
      <p
        v-if="error"
        class="mb-4 rounded-lg border border-n-ruby-7 bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
        role="alert"
      >
        {{ error }}
      </p>
      <p
        v-if="success"
        class="mb-4 rounded-lg border border-n-teal-7 bg-n-teal-2 p-3 text-sm text-n-teal-11"
        role="status"
      >
        {{ success }}
      </p>
      <p
        v-if="!canEdit"
        class="mb-4 flex items-center gap-2 rounded-lg bg-n-slate-2 p-3 text-sm text-n-slate-11"
      >
        <span class="i-lucide-lock-keyhole h-4 w-4" aria-hidden="true" />{{
          projectText(
            'CONFIG_READ_ONLY',
            'Você tem acesso de consulta às informações do projeto.'
          )
        }}
      </p>

      <div
        v-if="tab === 'general'"
        id="project-config-general"
        role="tabpanel"
        aria-labelledby="project-config-tab-general"
        class="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1.6fr)_minmax(280px,1fr)]"
      >
        <form
          class="flex min-w-0 flex-col gap-5"
          @submit.prevent="save('general')"
        >
          <header>
            <h3 class="text-base font-semibold">
              {{ projectText('CONFIG_INFORMATION', 'Informações do projeto') }}
            </h3>
            <p class="mt-1 text-sm text-n-slate-11">
              {{
                projectText(
                  'CONFIG_INFORMATION_HELP',
                  'Dados básicos e configuração geral do projeto.'
                )
              }}
            </p>
          </header>
          <fieldset
            :disabled="!canEdit || busy"
            class="grid min-w-0 grid-cols-1 gap-5 md:grid-cols-2"
          >
            <label class="flex min-w-0 flex-col gap-2 text-sm"
              ><span class="font-medium">{{
                projectText('CONFIG_NAME_REQUIRED', 'Nome *')
              }}</span
              ><input
                v-model="form.name"
                :class="controlClass"
                required
                maxlength="240"
            /></label>
            <label class="flex min-w-0 flex-col gap-2 text-sm"
              ><span class="font-medium">{{
                projectText('CONFIG_CODE', 'Código')
              }}</span
              ><input
                :value="project.key"
                :class="controlClass"
                :aria-label="projectText('CONFIG_CODE', 'Código')"
                readonly
            /></label>
            <div
              v-if="companyAvailable"
              class="flex min-w-0 flex-col gap-2 text-sm"
            >
              <span class="font-medium">{{
                projectText('CONFIG_COMPANY', 'Empresa do projeto')
              }}</span>
              <CompanyPicker
                v-model="form.company_id"
                :disabled="!canEdit || busy"
              />
            </div>
            <div
              class="min-w-0 rounded-lg border border-n-weak p-3 text-sm [&_input]:w-full [&_input]:rounded-md [&_input]:border [&_input]:border-n-weak [&_input]:bg-n-solid-1 [&_input]:p-2"
            >
              <ContactPicker
                v-model="form.contact_id"
                :disabled="project.contact_locked || !canEdit || busy"
              />
              <p
                v-if="project.contact_locked"
                class="mt-2 text-xs leading-relaxed text-n-slate-11"
              >
                {{
                  projectText(
                    'CUSTOMER_LINKED',
                    'O cliente é preservado porque o projeto possui registros de origem vinculados.'
                  )
                }}
              </p>
            </div>
            <label class="flex min-w-0 flex-col gap-2 text-sm">
              <span class="font-medium">{{
                projectText('CONFIG_OWNER', 'Responsável pelo projeto')
              }}</span>
              <select
                v-model="form.owner_id"
                :class="controlClass"
                required
                :disabled="!canTransfer || optionsLoading"
              >
                <option
                  v-if="
                    !ownerOptions.some(user => user.id === project.owner_id)
                  "
                  :value="project.owner_id"
                >
                  {{ project.owner?.name }}
                </option>
                <option
                  v-for="user in ownerOptions"
                  :key="user.id"
                  :value="user.id"
                >
                  {{ user.name }}
                </option>
              </select>
              <small class="leading-relaxed text-n-slate-11">{{
                projectText(
                  'OWNER_TRANSFER_HELP',
                  'Somente o proprietário atual ou um administrador pode transferir a responsabilidade.'
                )
              }}</small>
            </label>
            <label class="flex min-w-0 flex-col gap-2 text-sm"
              ><span class="font-medium">{{
                projectText('PRIORITY', 'Prioridade')
              }}</span
              ><select v-model="form.priority" :class="controlClass" required>
                <option
                  v-for="(label, value) in priorityLabels"
                  :key="value"
                  :value="value"
                >
                  {{ label }}
                </option>
              </select></label
            >
            <div class="col-span-full grid grid-cols-1 gap-5 md:grid-cols-3">
              <label class="flex min-w-0 flex-col gap-2 text-sm"
                ><span class="font-medium">{{
                  projectText('CONFIG_START', 'Data de início')
                }}</span
                ><input
                  v-model="form.starts_on"
                  :class="controlClass"
                  type="date"
              /></label>
              <label class="flex min-w-0 flex-col gap-2 text-sm"
                ><span class="font-medium">{{
                  projectText('CONFIG_DUE', 'Entrega prevista')
                }}</span
                ><input
                  v-model="form.due_on"
                  :class="controlClass"
                  type="date"
                  :min="form.starts_on || undefined"
              /></label>
              <label class="flex min-w-0 flex-col gap-2 text-sm"
                ><span class="font-medium">{{
                  projectText('CONFIG_STATUS', 'Situação')
                }}</span
                ><select v-model="form.status" :class="controlClass" required>
                  <option
                    v-for="(label, value) in statusLabels"
                    :key="value"
                    :value="value"
                    :disabled="
                      value === 'completed' && project.status !== 'completed'
                    "
                  >
                    {{ label }}
                  </option>
                </select></label
              >
            </div>
            <label class="flex min-w-0 flex-col gap-2 text-sm"
              ><span class="font-medium">{{
                projectText('VISIBILITY', 'Visibilidade')
              }}</span
              ><select v-model="form.visibility" :class="controlClass" required>
                <option value="members">
                  {{
                    projectText('MEMBERS', 'Participantes e administradores')
                  }}
                </option>
                <option value="account">
                  {{ projectText('ACCOUNT', 'Toda a conta pode consultar') }}
                </option>
                <option value="private">
                  {{ projectText('PRIVATE', 'Privado') }}
                </option>
              </select></label
            >
            <div class="flex items-center gap-2 text-sm text-n-slate-11">
              <span
                :class="
                  form.contact_id
                    ? 'i-lucide-building-2'
                    : 'i-lucide-folder-lock'
                "
                class="h-5 w-5"
                aria-hidden="true"
              />{{
                form.contact_id
                  ? projectText(
                      'CONFIG_CUSTOMER_PROJECT',
                      'Projeto com cliente vinculado'
                    )
                  : projectText('CONFIG_INTERNAL_PROJECT', 'Projeto interno')
              }}
            </div>
          </fieldset>
          <p
            v-if="optionsError"
            class="rounded-lg bg-n-ruby-2 p-3 text-sm text-n-ruby-11"
            role="alert"
          >
            {{ optionsError }}
            <button type="button" class="ml-2 underline" @click="loadOwners">
              {{ projectText('RETRY', 'Tentar novamente') }}
            </button>
          </p>
          <p
            v-if="project.status !== 'completed'"
            class="text-sm text-n-slate-11"
          >
            {{
              projectText(
                'CONFIG_COMPLETE_HELP',
                'Para concluir o projeto, registre a validação da entrega em Aceite e homologação.'
              )
            }}
          </p>
          <footer
            v-if="canEdit"
            class="flex flex-wrap gap-3 border-t border-n-weak pt-4"
          >
            <button type="submit" :class="primaryClass" :disabled="busy">
              <span class="i-lucide-save h-4 w-4" aria-hidden="true" />{{
                busy
                  ? projectText('CONFIG_SAVING', 'Salvando…')
                  : projectText('CONFIG_SAVE', 'Salvar alterações')
              }}
            </button>
            <button
              type="button"
              :class="buttonClass"
              :disabled="busy"
              @click="discard"
            >
              {{ projectText('CONFIG_DISCARD', 'Descartar alterações') }}
            </button>
          </footer>
        </form>

        <aside class="flex min-w-0 flex-col gap-4">
          <section class="rounded-xl border border-n-weak p-4">
            <h3 class="mb-4 text-sm font-semibold">
              {{ projectText('CONFIG_SUMMARY', 'Resumo do projeto') }}
            </h3>
            <dl class="grid grid-cols-2 gap-4 text-sm">
              <div>
                <dt class="mb-1 text-xs text-n-slate-11">
                  {{ projectText('CONFIG_START', 'Data de início') }}
                </dt>
                <dd class="font-medium">{{ formatDate(project.starts_on) }}</dd>
              </div>
              <div>
                <dt class="mb-1 text-xs text-n-slate-11">
                  {{ projectText('CONFIG_DUE', 'Entrega prevista') }}
                </dt>
                <dd class="font-medium">{{ formatDate(project.due_on) }}</dd>
              </div>
              <div>
                <dt class="mb-2 text-xs text-n-slate-11">
                  {{ projectText('PRIORITY', 'Prioridade') }}
                </dt>
                <dd>
                  <span
                    class="rounded-full px-2.5 py-1 text-xs font-medium"
                    :class="priorityTone(project.priority)"
                    >{{ priorityLabels[project.priority] }}</span
                  >
                </dd>
              </div>
              <div>
                <dt class="mb-2 text-xs text-n-slate-11">
                  {{ projectText('CONFIG_STATUS', 'Situação') }}
                </dt>
                <dd>
                  <span
                    class="rounded-full px-2.5 py-1 text-xs font-medium"
                    :class="statusTone(project.status)"
                    >{{ statusLabels[project.status] }}</span
                  >
                </dd>
              </div>
            </dl>
          </section>
          <section class="rounded-xl border border-n-weak p-4">
            <div class="mb-4 flex flex-wrap items-center justify-between gap-2">
              <h3 class="text-sm font-semibold">
                {{ projectText('CONFIG_CUSTOMER', 'Cliente e empresa') }}
              </h3>
              <RouterLink
                v-if="project.company && companyAvailable"
                class="inline-flex items-center gap-1 text-xs text-n-blue-11 hover:underline"
                :to="
                  masterRoute('jrc_customer_company', {
                    companyId: project.company.id,
                  })
                "
              >
                <span
                  class="i-lucide-external-link h-3.5 w-3.5"
                  aria-hidden="true"
                />{{ projectText('CONFIG_OPEN_COMPANY', 'Abrir ficha 360') }}
              </RouterLink>
            </div>
            <p
              v-if="project.company"
              class="mb-3 flex items-center gap-2 text-sm font-medium"
            >
              <span
                class="i-lucide-building-2 h-5 w-5 text-n-blue-11"
                aria-hidden="true"
              />{{ project.company.name }}
            </p>
            <div
              v-if="project.contact"
              class="flex items-center gap-3 rounded-lg bg-n-slate-2 p-3"
            >
              <span
                class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-xs font-semibold text-n-blue-11"
                >{{ initials(project.contact.name) }}</span
              >
              <div class="min-w-0">
                <p class="truncate text-sm font-medium">
                  {{ project.contact.name }}
                </p>
                <p
                  v-if="project.contact.email"
                  class="break-all text-xs text-n-slate-11"
                >
                  {{ project.contact.email }}
                </p>
              </div>
            </div>
            <p v-else class="text-sm text-n-slate-11">
              {{
                projectText(
                  'CONFIG_NO_CUSTOMER',
                  'Projeto interno, sem cliente vinculado.'
                )
              }}
            </p>
          </section>
          <section class="rounded-xl border border-n-weak p-4">
            <h3 class="mb-3 text-sm font-semibold">
              {{ projectText('CONFIG_PROGRESS', 'Progresso do projeto') }}
            </h3>
            <div class="flex items-center gap-3">
              <progress
                :value="project.progress"
                max="100"
                class="h-2 w-full overflow-hidden rounded-full accent-emerald-500 [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:bg-emerald-500 [&::-moz-progress-bar]:bg-emerald-500"
                :aria-label="
                  projectText('CONFIG_PROGRESS', 'Progresso do projeto')
                "
              /><strong class="text-sm">{{ project.progress }}%</strong>
            </div>
            <p class="mt-2 text-xs text-n-slate-11">
              {{ project.tasks_completed }}/{{ project.tasks_total }}
              {{ projectText('CONFIG_COMPLETED_TASKS', 'tarefas concluídas') }}
            </p>
            <h4 class="mb-3 mt-5 text-sm font-semibold">
              {{ projectText('CONFIG_IMPORTANT_DATES', 'Datas importantes') }}
            </h4>
            <dl class="space-y-3 text-xs">
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">
                  {{ projectText('CONFIG_CREATED', 'Criação do projeto') }}
                </dt>
                <dd>{{ formatDate(project.created_at) }}</dd>
              </div>
              <div class="flex justify-between gap-3">
                <dt class="text-n-slate-11">
                  {{ projectText('CONFIG_ACCEPTED_AT', 'Aceite e conclusão') }}
                </dt>
                <dd>{{ formatDate(project.completed_at) }}</dd>
              </div>
            </dl>
          </section>
        </aside>
      </div>

      <form
        v-else-if="tab === 'scope'"
        id="project-config-scope"
        role="tabpanel"
        aria-labelledby="project-config-tab-scope"
        class="flex flex-col gap-5"
        @submit.prevent="save('scope')"
      >
        <header>
          <h3 class="text-base font-semibold">
            {{ projectText('CONFIG_SCOPE_TITLE', 'Escopo e entregáveis') }}
          </h3>
          <p class="mt-1 text-sm text-n-slate-11">
            {{
              projectText(
                'CONFIG_SCOPE_HELP',
                'Descreva o objetivo, as entregas e os limites do projeto. As alterações ficam registradas no histórico.'
              )
            }}
          </p>
        </header>
        <label class="flex flex-col gap-2 text-sm"
          ><span class="font-medium">{{
            projectText('CONFIG_DESCRIPTION', 'Descrição do escopo')
          }}</span
          ><textarea
            v-model="form.description"
            :class="controlClass"
            rows="12"
            :disabled="!canEdit || busy"
            :placeholder="
              projectText(
                'CONFIG_SCOPE_PLACEHOLDER',
                'Objetivo do projeto, entregas previstas e condições acordadas…'
              )
            "
          />
        </label>
        <p class="flex items-center gap-2 text-sm text-n-slate-11">
          <span class="i-lucide-info h-4 w-4 shrink-0" aria-hidden="true" />{{
            projectText(
              'CONFIG_SCOPE_ACCEPTANCE_HELP',
              'Registre critérios de validação e evidências da entrega na subaba Aceite e homologação.'
            )
          }}
        </p>
        <footer
          v-if="canEdit"
          class="flex flex-wrap gap-3 border-t border-n-weak pt-4"
        >
          <button type="submit" :class="primaryClass" :disabled="busy">
            {{
              busy
                ? projectText('CONFIG_SAVING', 'Salvando…')
                : projectText('CONFIG_SAVE_SCOPE', 'Salvar escopo')
            }}</button
          ><button
            type="button"
            :class="buttonClass"
            :disabled="busy"
            @click="discard"
          >
            {{ projectText('CONFIG_DISCARD', 'Descartar alterações') }}
          </button>
        </footer>
      </form>

      <div
        v-else-if="tab === 'acceptance'"
        id="project-config-acceptance"
        role="tabpanel"
        aria-labelledby="project-config-tab-acceptance"
        class="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1.6fr)_minmax(280px,1fr)]"
      >
        <form
          class="flex min-w-0 flex-col gap-5"
          @submit.prevent="save('acceptance')"
        >
          <header>
            <h3 class="text-base font-semibold">
              {{ projectText('CONFIG_ACCEPTANCE', 'Aceite e homologação') }}
            </h3>
            <p class="mt-1 text-sm text-n-slate-11">
              {{
                projectText(
                  'CONFIG_ACCEPTANCE_HELP',
                  'Registre quem validou a entrega, os critérios atendidos e as evidências correspondentes.'
                )
              }}
            </p>
          </header>
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div class="rounded-lg border border-n-weak p-4">
              <span class="text-xs text-n-slate-11">{{
                projectText('TASKS_TOTAL', 'Total de tarefas')
              }}</span
              ><strong class="mt-1 block text-2xl">{{
                project.tasks_total
              }}</strong>
            </div>
            <div class="rounded-lg border border-n-weak p-4">
              <span class="text-xs text-n-slate-11">{{
                projectText('CONFIG_PENDING_TASKS', 'Pendentes para o aceite')
              }}</span
              ><strong
                class="mt-1 block text-2xl"
                :class="pendingTasks ? 'text-n-amber-11' : 'text-n-teal-11'"
                >{{ pendingTasks }}</strong
              >
            </div>
            <div class="rounded-lg border border-n-weak p-4">
              <span class="text-xs text-n-slate-11">{{
                projectText('CONFIG_ACCEPTANCE_STATUS', 'Situação do aceite')
              }}</span
              ><strong
                class="mt-2 block text-sm"
                :class="
                  project.completed_at ? 'text-n-teal-11' : 'text-n-slate-11'
                "
                >{{
                  project.completed_at
                    ? projectText('CONFIG_ACCEPTANCE_RECORDED', 'Registrado')
                    : projectText('CONFIG_ACCEPTANCE_PENDING', 'Pendente')
                }}</strong
              >
            </div>
          </div>
          <label class="flex flex-col gap-2 text-sm"
            ><span class="font-medium">{{
              projectText(
                'CONFIG_ACCEPTANCE_NOTES',
                'Registro do aceite, critérios e evidências'
              )
            }}</span
            ><textarea
              v-model="form.acceptance_notes"
              :class="controlClass"
              rows="9"
              :disabled="!canEdit || busy"
              :placeholder="
                projectText(
                  'CONFIG_ACCEPTANCE_PLACEHOLDER',
                  'Quem validou, o que foi aceito e onde consultar as evidências da entrega.'
                )
              "
            />
          </label>
          <p
            class="rounded-lg bg-n-slate-2 p-3 text-sm leading-relaxed text-n-slate-11"
          >
            {{
              projectText(
                'CONFIG_ACCEPTANCE_POLICY',
                'A conclusão exige que todas as tarefas estejam concluídas ou canceladas e que o aceite esteja registrado. O responsável pela ação e a data são gravados no projeto.'
              )
            }}
          </p>
          <p v-if="pendingTasks" class="text-sm text-n-amber-11">
            {{
              projectText(
                'CONFIG_PENDING_HELP',
                'Ainda há tarefas pendentes. Revise a execução antes de concluir o projeto.'
              )
            }}
          </p>
          <p
            v-if="project.status === 'canceled'"
            class="text-sm text-n-slate-11"
          >
            {{
              projectText(
                'CONFIG_REOPEN_HELP',
                'Reabra o projeto em Dados gerais para registrar sua conclusão.'
              )
            }}
          </p>
          <footer
            v-if="canEdit"
            class="flex flex-wrap gap-3 border-t border-n-weak pt-4"
          >
            <button type="submit" :class="buttonClass" :disabled="busy">
              {{ projectText('CONFIG_SAVE_ACCEPTANCE', 'Salvar registro') }}
            </button>
            <button
              v-if="project.status !== 'completed'"
              type="button"
              :class="primaryClass"
              :disabled="busy || !canComplete"
              @click="save('acceptance', true)"
            >
              <span class="i-lucide-check-check h-4 w-4" aria-hidden="true" />{{
                projectText(
                  'CONFIG_COMPLETE_PROJECT',
                  'Registrar aceite e concluir'
                )
              }}
            </button>
          </footer>
        </form>
        <aside class="flex min-w-0 flex-col gap-4">
          <section class="rounded-xl border border-n-weak p-4">
            <h3 class="mb-4 text-sm font-semibold">
              {{
                projectText('CONFIG_ACCEPTANCE_RECORD', 'Registro de conclusão')
              }}
            </h3>
            <dl class="space-y-4 text-sm">
              <div>
                <dt class="mb-1 text-xs text-n-slate-11">
                  {{ projectText('CONFIG_ACCEPTED_BY', 'Registrado por') }}
                </dt>
                <dd class="font-medium">
                  {{
                    project.accepted_by?.name ||
                    projectText('CONFIG_NOT_RECORDED', 'Ainda não registrado')
                  }}
                </dd>
              </div>
              <div>
                <dt class="mb-1 text-xs text-n-slate-11">
                  {{ projectText('CONFIG_ACCEPTED_AT', 'Aceite e conclusão') }}
                </dt>
                <dd>{{ formatDate(project.completed_at) }}</dd>
              </div>
            </dl>
          </section>
          <section class="rounded-xl border border-n-weak p-4">
            <h3 class="mb-4 text-sm font-semibold">
              {{
                projectText('CONFIG_HISTORY', 'Últimas alterações do projeto')
              }}
            </h3>
            <ol class="space-y-4">
              <li
                v-for="event in projectEvents"
                :key="event.id"
                class="flex gap-3"
              >
                <span
                  class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-n-blue-3 text-xs font-semibold text-n-blue-11"
                  >{{ initials(event.actor?.name) }}</span
                >
                <div class="min-w-0 text-xs">
                  <p class="font-medium">
                    {{ event.actor?.name || projectText('SYSTEM', 'Sistema') }}
                  </p>
                  <p class="mt-1 text-n-slate-11">
                    {{
                      event.action === 'projects.project.created'
                        ? projectText('EVENT_PROJECT_CREATED', 'Projeto criado')
                        : projectText(
                            'EVENT_PROJECT_UPDATED',
                            'Projeto atualizado'
                          )
                    }}
                  </p>
                  <time
                    :datetime="event.created_at"
                    class="mt-1 block text-n-slate-11"
                    >{{ formatDate(event.created_at) }}</time
                  >
                </div>
              </li>
            </ol>
            <p v-if="!projectEvents.length" class="text-sm text-n-slate-11">
              {{ projectText('NO_ACTIVITY', 'Nenhuma atividade registrada.') }}
            </p>
          </section>
        </aside>
      </div>

      <section
        v-else
        id="project-config-board"
        role="tabpanel"
        aria-labelledby="project-config-tab-board"
        class="flex flex-col gap-4"
      >
        <ResourceManager
          v-if="canManageBoard && project.columns?.length"
          :schema="columnSchema"
          :endpoint="`projects/projects/${project.id}/boards/${project.columns[0].board_id}/columns`"
          payload-key="board_column"
          @changed="emit('changed')"
        />
        <template v-else>
          <header>
            <h3 class="text-base font-semibold">
              {{ projectText('CONFIG_COLUMNS', 'Colunas do quadro') }}
            </h3>
            <p class="mt-1 text-sm text-n-slate-11">
              {{
                !openProject
                  ? projectText(
                      'CONFIG_BOARD_CLOSED',
                      'Reabra o projeto para alterar a configuração do quadro.'
                    )
                  : projectText(
                      'CONFIG_BOARD_READ_ONLY',
                      'Configuração disponível para consulta conforme suas permissões.'
                    )
              }}
            </p>
          </header>
          <div
            v-if="project.columns?.length"
            class="overflow-x-auto rounded-lg border border-n-weak"
          >
            <table class="w-full text-left text-sm">
              <thead class="bg-n-slate-2 text-xs text-n-slate-11">
                <tr>
                  <th class="p-3">
                    {{ projectText('CONFIG_COLUMN', 'Coluna') }}
                  </th>
                  <th class="p-3">
                    {{ projectText('TASK_STATUS', 'Situação das tarefas') }}
                  </th>
                  <th class="p-3">
                    {{ projectText('CONFIG_ORDER', 'Ordem') }}
                  </th>
                  <th class="p-3">
                    {{ projectText('CONFIG_WIP', 'Limite WIP') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="column in project.columns"
                  :key="column.id"
                  class="border-t border-n-weak"
                >
                  <td class="p-3 font-medium">{{ column.name }}</td>
                  <td class="p-3">
                    <span
                      class="rounded-full px-2 py-1 text-xs"
                      :class="statusTone(column.status_key)"
                      >{{
                        projectTaskStatuses[column.status_key] ||
                        column.status_key
                      }}</span
                    >
                  </td>
                  <td class="p-3">{{ column.position }}</td>
                  <td class="p-3">
                    {{
                      column.wip_limit ??
                      projectText('CONFIG_NO_LIMIT', 'Sem limite')
                    }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p
            v-else
            class="rounded-lg bg-n-slate-2 p-6 text-center text-sm text-n-slate-11"
          >
            {{
              projectText(
                'CONFIG_NO_COLUMNS',
                'Nenhuma coluna configurada para este projeto.'
              )
            }}
          </p>
        </template>
        <p
          class="flex items-start gap-2 rounded-lg bg-n-blue-2 p-3 text-sm leading-relaxed text-n-slate-11"
        >
          <span
            class="i-lucide-shield-check mt-0.5 h-4 w-4 shrink-0 text-n-blue-11"
            aria-hidden="true"
          />{{
            projectText(
              'CONFIG_BOARD_PROTECTION',
              'O quadro preserva pelo menos uma coluna A fazer e uma Concluído. Colunas com tarefas não podem ser excluídas nem receber um estado incompatível.'
            )
          }}
        </p>
      </section>
    </div>
  </section>
</template>
