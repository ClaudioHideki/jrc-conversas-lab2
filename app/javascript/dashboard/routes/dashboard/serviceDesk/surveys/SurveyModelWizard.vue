<script setup>
import { surveyClasses } from './surveyClasses';
import {
  reactive,
  toRefs,
  ref,
  computed,
  nextTick,
  onMounted,
  onBeforeUnmount,
} from 'vue';
import SurveyModelsAPI from 'dashboard/api/serviceDeskSurveyModels';
import SurveyRuleTemplatePanel from '../../jrcRelationship/SurveyRuleTemplatePanel.vue';
import SurveyModelPreview from './SurveyModelPreview.vue';
import { beginSurveyModelPresentation } from './presentation';
import {
  STEPS,
  CHANNELS,
  ROLES,
  DAYS,
  stable,
  clone,
  key,
  newModel,
  setKind,
  addQuestion as appendQuestion,
  moveQuestion as reorderQuestion,
  validateStep,
  allErrors,
  messageErrors,
} from './modelForm';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  unit: { type: Object, required: true },
  options: { type: Object, required: true },
  record: { type: Object, default: null },
  api: { type: Object, default: () => SurveyModelsAPI },
});
const emit = defineEmits(['close', 'saved', 'published']);
const surveyLinkMarker = '{{survey_link}}';
defineOptions({ name: 'SurveyModelWizard' });
const state = reactive(
  (() => {
    const model = props.record
      ? clone(props.record.payload)
      : newModel(props.unit, props.options);
    model.rules.send_window = {
      ...newModel(props.unit, props.options).rules.send_window,
      ...model.rules.send_window,
    };
    return {
      model,
      step: 0,
      steps: STEPS,
      channels: CHANNELS,
      roles: ROLES,
      days: DAYS,
      modelId: props.record?.id || null,
      version: props.record?.lock_version ?? null,
      baseline: stable(model),
      busy: false,
      errors: [],
      success: '',
      editedQuestion: 0,
      addType: 'text',
      expandedChannel: 'whatsapp',
      confirmPublication: false,
      leavePrompt: false,
      operationUnknown: false,
      publicationKey: null,
      controller: null,
      alive: true,
      focusReturn: null,
      releasePresentation: null,
      permissions: props.record?.permissions || {
        edit: true,
        publish: true,
        manage_permissions: props.options.role === 'administrator',
      },
    };
  })()
);
const {
  model,
  step,
  steps,
  channels,
  roles,
  days,
  modelId,
  busy,
  errors,
  success,
  editedQuestion,
  addType,
  expandedChannel,
  confirmPublication,
  leavePrompt,
  operationUnknown,
  permissions,
} = toRefs(state);
const body = ref(null);
const heading = ref(null);
const dialog = ref(null);
const dirty = computed(() => {
  return stable(state.model) !== state.baseline;
});
const question = computed(() => {
  return state.model.questions[state.editedQuestion];
});
const chosenUnit = computed(() => {
  return (
    props.options.units?.find(
      row => String(row.id) === String(state.model.unit_id)
    ) || props.unit
  );
});
const operators = computed(() => {
  return [
    ...new Map(
      (props.options.units || []).map(u => [
        String(u.operator_id),
        { id: u.operator_id, name: u.operator_name },
      ])
    ).values(),
  ];
});
const availableUnits = computed(() => {
  return (props.options.units || []).filter(
    u => String(u.operator_id) === String(state.model.operator_id)
  );
});
const enabledChannels = computed(() => {
  return state.channels.filter(row => state.model.channels[row.key].enabled);
});
const templateInboxes = computed(() => {
  return (props.options.inboxes || [])
    .filter(row => row.channel === 'whatsapp')
    .map(row => [row.id, row.name]);
});
const eventLabel = computed(() => {
  return {
    closed: 'Após o encerramento do chamado',
    first_agent_response: 'Após a primeira resposta pública do atendente',
    manual: 'Envio manual autorizado',
  }[state.model.rules.event];
});
const summary = computed(() => {
  return [
    {
      title: 'Informações',
      detail: `${state.model.name} · ${state.model.kind.toUpperCase()}`,
      tone: 'purple',
      icon: 'i-lucide-info',
    },
    {
      title: 'Perguntas',
      detail: `${state.model.questions.length} perguntas · escala principal ${state.model.questions[0]?.min} a ${state.model.questions[0]?.max}`,
      tone: 'blue',
      icon: 'i-lucide-list-ordered',
    },
    {
      title: 'Canais de envio',
      detail: enabledChannels.value.map(c => c.label).join(', '),
      tone: 'green',
      icon: 'i-lucide-send',
    },
    {
      title: 'Regras de envio',
      detail: `${eventLabel.value} · intervalo ${state.model.rules.delay_minutes} min`,
      tone: 'amber',
      icon: 'i-lucide-clock',
    },
    {
      title: 'Permissões',
      detail: `${state.model.permissions.team_ids.length || 'Todas as'} equipes autorizadas · acesso nativo preservado`,
      tone: 'pink',
      icon: 'i-lucide-shield-check',
    },
  ];
});
function beforeUnload(event) {
  if (dirty.value || state.busy) {
    event.preventDefault();
    event.returnValue = '';
  }
}
function changeKind(kind) {
  setKind(state.model, kind);
  state.errors = [];
}
function changeOperator() {
  state.model.unit_id = null;
}
function pickUnit() {
  const u = props.options.units.find(
    row => String(row.id) === String(state.model.unit_id)
  );
  if (u) state.model.operator_id = u.operator_id;
}
function scrollTop() {
  nextTick(() => {
    body.value?.scrollTo?.({ top: 0 });
    heading.value?.focus();
  });
}
function go(targetStep) {
  if (state.busy || state.operationUnknown) return;
  const validationErrors =
    targetStep > state.step
      ? Array.from({ length: targetStep }, (_, i) =>
          validateStep(state.model, i)
        ).flat()
      : [];
  if (validationErrors.length) {
    state.errors = validationErrors;
    state.step = validationErrors[0].step;
    scrollTop();
    return;
  }
  state.step = Math.max(0, Math.min(5, targetStep));
  state.errors = [];
  state.success = '';
  scrollTop();
}
function addQuestion() {
  if (state.model.questions.length < 20)
    state.editedQuestion = appendQuestion(state.model, state.addType);
}
function removeQuestion(index) {
  const q = state.model.questions[index];
  if (index === 0) return;
  if (state.model.questions.some(row => row.condition?.question === q.key)) {
    state.errors = [
      {
        step: 1,
        message: 'Remova primeiro as condições que dependem desta pergunta.',
      },
    ];
    return;
  }
  state.model.questions.splice(index, 1);
  state.editedQuestion = Math.min(
    state.editedQuestion,
    state.model.questions.length - 1
  );
}
function moveQuestion(index, offset) {
  if (reorderQuestion(state.model, index, offset))
    state.editedQuestion = index + offset;
  else
    state.errors = [
      { step: 1, message: 'Esta ordem quebraria uma condição de exibição.' },
    ];
}
function thresholdInput(event) {
  if (event.target.value === '') delete state.model.settings.low_threshold;
  else state.model.settings.low_threshold = Number(event.target.value);
}
function formatName(q) {
  if (q.presentation === 'stars') return 'Avaliação';
  return {
    scale: 'Escala numérica',
    choice: 'Múltipla escolha',
    text: 'Texto aberto',
  }[q.type];
}
function questionTone(q, index) {
  if (index === 0) return 'purple';
  if (q.type === 'text') return 'amber';
  return q.type === 'choice' ? 'blue' : 'green';
}
function addOption(q) {
  if (q.options.length < 30)
    q.options.push({ value: `op_${key().slice(-8)}`, label: '' });
}
function inboxes(channel) {
  return (props.options.inboxes || []).filter(i => i.channel === channel);
}
function toggleDay(day) {
  const selectedDays = state.model.rules.send_window.days;
  state.model.rules.send_window.days = selectedDays.includes(day)
    ? selectedDays.filter(d => d !== day)
    : [...selectedDays, day].sort();
}
function moveChannel(index, offset) {
  const list = state.model.rules.channel_order;
  const target = index + offset;
  if (target >= 0 && target < list.length)
    [list[index], list[target]] = [list[target], list[index]];
}
function permissionLabel(permissionKey) {
  return {
    edit_roles: 'Editar',
    publish_roles: 'Publicar',
    response_roles: 'Respostas',
    report_roles: 'Relatórios',
  }[permissionKey];
}
function channelLabel(channelKey) {
  return (
    state.channels.find(row => row.key === channelKey)?.label || channelKey
  );
}
function chooseCondition(q, event) {
  q.condition = event.target.value
    ? { question: event.target.value, operator: 'eq', value: '' }
    : null;
}
function close() {
  if (state.busy) return;
  if (dirty.value || state.operationUnknown) state.leavePrompt = true;
  else emit('close');
}
function discard() {
  emit('close');
}
function onKey(event) {
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
  }
  if (event.key !== 'Tab') return;
  const nodes = [
    ...dialog.value.querySelectorAll(
      'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), a[href], [tabindex="0"]'
    ),
  ].filter(el => el.getClientRects().length);
  if (!nodes.length) {
    event.preventDefault();
    return;
  }
  const first = nodes[0];
  const last = nodes[nodes.length - 1];
  if (
    event.shiftKey &&
    (document.activeElement === first ||
      document.activeElement === dialog.value)
  ) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
}
async function persist() {
  const snapshot = clone(state.model);
  if (!state.permissions.edit && dirty.value) {
    throw Object.assign(new Error('Read-only survey draft'), {
      response: { status: 403 },
    });
  }
  const response = state.permissions.edit
    ? await props.api.save(
        props.accountId,
        snapshot,
        state.modelId,
        state.version,
        { signal: state.controller.signal }
      )
    : { data: { id: state.modelId, lock_version: state.version } };
  if (!state.alive) return null;
  state.modelId = response.data.id;
  state.version = response.data.lock_version;
  const check = await props.api.get(props.accountId, state.modelId, {
    signal: state.controller.signal,
  });
  if (!state.alive) return null;
  if (
    stable(check.data.payload) !== stable(snapshot) ||
    check.data.lock_version !== state.version
  )
    throw Object.assign(new Error('Survey state conflict'), {
      response: { status: 409 },
    });
  state.baseline = stable(snapshot);
  state.permissions = check.data.permissions;
  emit('saved', check.data);
  return check.data;
}
function handleError(error) {
  if (!state.alive || error?.code === 'ERR_CANCELED') return;
  state.errors = messageErrors(error);
  const status = error?.response?.status;
  state.operationUnknown = !status || status >= 500;
  if (status === 422) state.publicationKey = null;
  const first = state.errors.find(row => row.step >= 0);
  if (first) state.step = first.step;
  scrollTop();
}
async function save(andClose = false) {
  if (state.busy || state.operationUnknown) return;
  state.busy = true;
  state.errors = [];
  state.success = '';
  state.controller = new AbortController();
  try {
    const row = await persist();
    if (!row) return;
    state.success =
      'Rascunho salvo e relido. A publicação anterior não foi alterada.';
    state.leavePrompt = false;
    if (andClose) emit('close');
  } catch (e) {
    handleError(e);
  } finally {
    if (state.alive) state.busy = false;
  }
}
function acceptPublication(row) {
  state.model = clone(row.payload);
  state.baseline = stable(state.model);
  state.version = row.lock_version;
  state.permissions = row.permissions;
  state.confirmPublication = false;
  state.publicationKey = null;
  state.operationUnknown = false;
  state.success = `Versão ${row.published_version} publicada e relida. Nenhuma mensagem foi enviada por esta ação.${props.options.automation_enabled ? '' : ' Motor automático de pesquisas: desligado. Publicar não liga o motor.'}`;
  emit('published', row);
}
async function publish() {
  if (
    state.busy ||
    state.operationUnknown ||
    !state.confirmPublication ||
    !state.permissions.publish
  )
    return;
  state.errors = allErrors(state.model);
  if (state.errors.length) {
    state.step = state.errors[0].step;
    scrollTop();
    return;
  }
  state.busy = true;
  state.success = '';
  state.controller = new AbortController();
  try {
    if (!state.modelId || dirty.value) await persist();
    if (!state.alive) return;
    await props.api.validate(props.accountId, state.modelId, {
      signal: state.controller.signal,
    });
    state.publicationKey ||= key();
    await props.api.publish(
      props.accountId,
      state.modelId,
      state.version,
      state.publicationKey,
      { signal: state.controller.signal }
    );
    const check = await props.api.get(props.accountId, state.modelId, {
      signal: state.controller.signal,
    });
    if (!state.alive) return;
    if (check.data.publication_key !== state.publicationKey)
      throw new Error('Publication not confirmed');
    acceptPublication(check.data);
  } catch (e) {
    handleError(e);
  } finally {
    if (state.alive) state.busy = false;
  }
}
async function reconcile() {
  if (state.busy) return;
  state.busy = true;
  state.controller = new AbortController();
  try {
    let row;
    if (state.modelId)
      row = (
        await props.api.get(props.accountId, state.modelId, {
          signal: state.controller.signal,
        })
      ).data;
    else {
      const response = await props.api.lookup(
        props.accountId,
        state.model.unit_id,
        state.model.code,
        { signal: state.controller.signal }
      );
      row = response.data.payload[0];
    }
    if (!state.alive) return;
    if (
      row &&
      state.publicationKey &&
      row.publication_key === state.publicationKey
    )
      acceptPublication(row);
    else if (row && stable(row.payload) === stable(state.model)) {
      state.modelId = row.id;
      state.version = row.lock_version;
      state.baseline = stable(state.model);
      state.permissions = row.permissions;
      state.success =
        'Rascunho confirmado. A publicação ainda precisa de confirmação.';
      state.operationUnknown = false;
    } else if (!row && !state.modelId) {
      state.operationUnknown = false;
      state.success =
        'Nenhum rascunho com este código foi encontrado. Você pode salvar novamente.';
    } else
      throw Object.assign(new Error('Survey state conflict'), {
        response: { status: 409 },
      });
    state.errors = [];
  } catch (e) {
    handleError(e);
  } finally {
    if (state.alive) state.busy = false;
  }
}

onMounted(() => {
  state.focusReturn = document.activeElement;
  state.releasePresentation = beginSurveyModelPresentation();
  state.previousOverflow = document.body.style.overflow;
  document.body.style.overflow = 'hidden';
  window.addEventListener('beforeunload', beforeUnload);
  nextTick(() => dialog.value?.focus());
});
onBeforeUnmount(() => {
  state.alive = false;
  state.controller?.abort();
  state.releasePresentation?.();
  document.body.style.overflow = state.previousOverflow || '';
  window.removeEventListener('beforeunload', beforeUnload);
  state.focusReturn?.focus?.({ preventScroll: true });
});
defineExpose({
  ...toRefs(state),
  dirty,
  question,
  chosenUnit,
  operators,
  availableUnits,
  enabledChannels,
  templateInboxes,
  eventLabel,
  summary,
  beforeUnload,
  changeKind,
  changeOperator,
  pickUnit,
  go,
  scrollTop,
  addQuestion,
  removeQuestion,
  moveQuestion,
  thresholdInput,
  formatName,
  questionTone,
  addOption,
  inboxes,
  toggleDay,
  moveChannel,
  permissionLabel,
  channelLabel,
  chooseCondition,
  close,
  discard,
  onKey,
  persist,
  handleError,
  save,
  publish,
  acceptPublication,
  reconcile,
});
</script>

<template>
  <Teleport to="body">
    <div
      :class="surveyClasses('sv-backdrop')"
      @click.self="close"
    >
      <section
        ref="dialog"
        :class="surveyClasses('sv-modal')"
        role="dialog"
        aria-modal="true"
        aria-labelledby="sv-model-title"
        tabindex="-1"
        @keydown="onKey"
      >
        <header :class="surveyClasses('sv-modal-header')">
          <div :class="surveyClasses('sv-title-icon')">
            <span
              class="i-lucide-chart-no-axes-combined"
              aria-hidden="true"
            />
          </div>
          <div>
            <p :class="surveyClasses('sv-eyebrow')">
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SERVICE_DESK_MODELOS_DE_PESQUISA_17EBE3'
                )
              }}
            </p>
            <h2 id="sv-model-title">
              {{
                modelId
                  ? 'Editar pesquisa de satisfação'
                  : 'Nova pesquisa de satisfação'
              }}
            </h2>
            <p>
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CONFIGURE_AS_PERGUNTAS_OS_CANAIS_D16360'
                )
              }}
            </p>
          </div>
          <button
            type="button"
            :class="surveyClasses('sv-close')"
            :aria-label="
              $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.FECHAR_EDITOR_C75A3E')
            "
            :disabled="busy"
            @click="close"
          >
            {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_8DB71E') }}
          </button>
        </header>
        <nav
          :class="surveyClasses('sv-stepper')"
          :aria-label="
            $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.ETAPAS_DA_PESQUISA_CB879E')
          "
        >
          <button
            v-for="(label, index) in steps"
            :key="label"
            type="button"
            :class="
              surveyClasses([
                'sv-step',
                { current: step === index, done: step > index },
              ])
            "
            :aria-current="step === index ? 'step' : null"
            :disabled="busy || operationUnknown"
            @click="go(index)"
          >
            <span>{{ step > index ? '✓' : index + 1 }}</span>
            {{ label }}
          </button>
        </nav>
        <div
          ref="body"
          :class="surveyClasses('sv-modal-body')"
        >
          <div
            v-if="errors.length"
            :class="surveyClasses('sv-alert sv-alert-error')"
            role="alert"
          >
            <strong>
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.REVISE_ANTES_DE_CONTINUAR_476139'
                )
              }}
            </strong>
            <p
              v-for="(error, i) in errors"
              :key="i"
            >
              {{ error.step >= 0 ? `${steps[error.step]}: ` : ''
              }}{{ error.message }}
            </p>
            <button
              v-if="operationUnknown"
              type="button"
              :class="surveyClasses('sv-button')"
              :disabled="busy"
              @click="reconcile"
            >
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.VERIFICAR_A_OPERACAO_NO_SERVIDOR_6FC14C'
                )
              }}
            </button>
          </div>
          <div
            v-if="success"
            role="status"
            :class="surveyClasses('sv-alert sv-alert-success')"
          >
            {{ success }}
          </div>
          <div :class="surveyClasses('sv-workspace')">
            <fieldset
              :class="surveyClasses('sv-main')"
              :disabled="
                busy || operationUnknown || (!permissions.edit && step !== 5)
              "
            >
              <div :class="surveyClasses('sv-section-heading')">
                <span
                  :class="
                    surveyClasses([
                      'sv-section-icon',
                      ['purple', 'blue', 'green', 'amber', 'pink', 'purple'][
                        step
                      ],
                    ])
                  "
                >
                  <span
                    :class="
                      [
                        'i-lucide-info',
                        'i-lucide-list-ordered',
                        'i-lucide-send',
                        'i-lucide-clock',
                        'i-lucide-shield-check',
                        'i-lucide-check-check',
                      ][step]
                    "
                  />
                </span>
                <div>
                  <h3
                    ref="heading"
                    tabindex="-1"
                  >
                    {{
                      [
                        'Informações da pesquisa',
                        'Perguntas da pesquisa',
                        'Canais de envio',
                        'Regras de envio',
                        'Permissões e visibilidade',
                        'Revisão e publicação',
                      ][step]
                    }}
                  </h3>
                  <p>
                    {{
                      [
                        'Defina a identidade, o indicador e o escopo do modelo.',
                        'Adicione, edite e organize as perguntas do formulário.',
                        'Escolha os canais elegíveis e configure suas identidades.',
                        'Defina o momento e as condições para avaliar o envio.',
                        'Os acessos abaixo sempre respeitam as permissões nativas.',
                        'Confira todas as etapas antes de publicar uma nova versão.',
                      ][step]
                    }}
                  </p>
                </div>
              </div>
              <div
                v-if="step === 0"
                :class="surveyClasses('sv-fields')"
              >
                <label>
                  <span>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NOME_DA_PESQUISA_34A05B'
                      )
                    }}
                    <b :class="surveyClasses('sv-required')">
                      {{
                        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_684888')
                      }}
                    </b>
                  </span>
                  <input
                    v-model="model.name"
                    data-testid="survey-name"
                    maxlength="120"
                    :placeholder="
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EX_AVALIACAO_DO_ATENDIMENTO_38A733'
                      )
                    "
                  />
                </label>
                <label>
                  {{
                    $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.DESCRICAO_46332F')
                  }}
                  <textarea
                    v-model="model.description"
                    maxlength="1000"
                    rows="3"
                    :placeholder="
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EXPLIQUE_O_OBJETIVO_DESTA_PESQUISA_4C3FAD'
                      )
                    "
                  />
                  <small :class="surveyClasses('sv-count')">
                    {{ model.description.length
                    }}{{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.1000_73D0B1') }}
                  </small>
                </label>
                <label>
                  <span>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TIPO_DE_PESQUISA_F993D8'
                      )
                    }}
                    <b :class="surveyClasses('sv-required')">
                      {{
                        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_684888')
                      }}
                    </b>
                  </span>
                </label>
                <div :class="surveyClasses('sv-kind-grid')">
                  <button
                    v-for="kind in ['nps', 'csat', 'ces']"
                    :key="kind"
                    type="button"
                    :class="
                      surveyClasses([
                        'sv-kind',
                        { selected: model.kind === kind },
                        { nps: 'purple', csat: 'amber', ces: 'pink' }[kind],
                      ])
                    "
                    :aria-pressed="model.kind === kind"
                    @click="changeKind(kind)"
                  >
                    <span
                      :class="
                        {
                          nps: 'i-lucide-sparkles',
                          csat: 'i-lucide-star',
                          ces: 'i-lucide-zap',
                        }[kind]
                      "
                    />
                    <strong>{{ kind.toUpperCase() }}</strong>
                    <small>
                      {{
                        {
                          nps: 'Recomendação · 0 a 10',
                          csat: 'Satisfação',
                          ces: 'Facilidade / esforço',
                        }[kind]
                      }}
                    </small>
                  </button>
                </div>
                <label :class="surveyClasses('sv-check-row')">
                  <input
                    v-model="model.active"
                    :disabled="!permissions.edit"
                    type="checkbox"
                    role="switch"
                  />
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.MODELO_ATIVO_APOS_A_PUBLICACAO_2C04B9'
                    )
                  }}
                </label>
                <p :class="surveyClasses('sv-help')">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RASCUNHO_NAO_DISPARA_PESQUISA_A_5A2D24'
                    )
                  }}
                </p>
                <div :class="surveyClasses('sv-two')">
                  <label>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EMPRESA_OPERADORA_212127'
                      )
                    }}
                    <select
                      v-model="model.operator_id"
                      disabled
                      @change="changeOperator"
                    >
                      <option :value="null">
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SELECIONE_987D5B'
                          )
                        }}
                      </option>
                      <option
                        v-for="op in operators"
                        :key="op.id"
                        :value="op.id"
                      >
                        {{ op.name }}
                      </option>
                    </select>
                  </label>
                  <label>
                    <span>
                      {{
                        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.UNIDADE_208F2C')
                      }}
                      <b :class="surveyClasses('sv-required')">
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_684888')
                        }}
                      </b>
                    </span>
                    <select
                      v-model="model.unit_id"
                      disabled
                      @change="pickUnit"
                    >
                      <option :value="null">
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SELECIONE_987D5B'
                          )
                        }}
                      </option>
                      <option
                        v-for="u in availableUnits"
                        :key="u.id"
                        :value="u.id"
                      >
                        {{ u.name }}
                      </option>
                    </select>
                  </label>
                </div>
                <p :class="surveyClasses('sv-help')">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.O_ESCOPO_VEM_DA_UNIDADE_C3DB22'
                    )
                  }}
                </p>
                <label>
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CODIGO_ESTAVEL_A92C8F'
                    )
                  }}
                  <input
                    v-model="model.code"
                    :readonly="!!modelId"
                    maxlength="32"
                  />
                  <small>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.UNICO_NESTA_UNIDADE_APOS_SALVAR_396C80'
                      )
                    }}
                  </small>
                </label>
              </div>
              <div
                v-if="step === 1"
                :class="surveyClasses('sv-fields')"
              >
                <div :class="surveyClasses('sv-add-question')">
                  <select
                    v-model="addType"
                    :aria-label="
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.FORMATO_DA_NOVA_PERGUNTA_463133'
                      )
                    "
                  >
                    <option value="text">
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TEXTO_ABERTO_B620A0'
                        )
                      }}
                    </option>
                    <option value="choice">
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.MULTIPLA_ESCOLHA_E5317F'
                        )
                      }}
                    </option>
                    <option value="scale">
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ESCALA_NUMERICA_14957F'
                        )
                      }}
                    </option>
                    <option value="rating">
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.AVALIACAO_EM_ESTRELAS_AE8C72'
                        )
                      }}
                    </option>
                  </select>
                  <button
                    type="button"
                    :class="surveyClasses('sv-button sv-primary')"
                    :disabled="model.questions.length >= 20"
                    @click="addQuestion"
                  >
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ADICIONAR_PERGUNTA_FD5D96'
                      )
                    }}
                  </button>
                </div>
                <article
                  v-for="(q, i) in model.questions"
                  :key="`${q.key}-${i}`"
                  :class="
                    surveyClasses([
                      'sv-question-card',
                      { editing: editedQuestion === i },
                    ])
                  "
                >
                  <div :class="surveyClasses('sv-question-top')">
                    <span
                      :class="
                        surveyClasses([
                          'sv-question-number',
                          questionTone(q, i),
                        ])
                      "
                    >
                      {{ i + 1 }}
                    </span>
                    <button
                      type="button"
                      :class="surveyClasses('sv-question-select')"
                      @click="editedQuestion = editedQuestion === i ? -1 : i"
                    >
                      <span
                        :class="surveyClasses(['sv-badge', questionTone(q, i)])"
                      >
                        {{ i === 0 ? model.kind.toUpperCase() : formatName(q) }}
                      </span>
                      <strong>{{ q.text || 'Nova pergunta' }}</strong>
                      <small>
                        {{ q.required ? 'Obrigatória' : 'Opcional'
                        }}{{
                          q.type === 'scale'
                            ? ` · Escala de ${q.min} a ${q.max}`
                            : ''
                        }}
                      </small>
                    </button>
                    <div :class="surveyClasses('sv-question-actions')">
                      <button
                        v-if="i > 0"
                        type="button"
                        :disabled="i === 1"
                        :aria-label="`Mover pergunta ${i + 1} para cima`"
                        @click="moveQuestion(i, -1)"
                      >
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_D2E966')
                        }}
                      </button>
                      <button
                        v-if="i > 0"
                        type="button"
                        :disabled="i === model.questions.length - 1"
                        :aria-label="`Mover pergunta ${i + 1} para baixo`"
                        @click="moveQuestion(i, 1)"
                      >
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_07A2AB')
                        }}
                      </button>
                      <button
                        v-if="i > 0"
                        type="button"
                        :aria-label="`Remover pergunta ${i + 1}`"
                        @click="removeQuestion(i)"
                      >
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_8DB71E')
                        }}
                      </button>
                    </div>
                  </div>
                  <div
                    v-if="editedQuestion === i"
                    :class="surveyClasses('sv-question-editor')"
                  >
                    <label>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TEXTO_DA_PERGUNTA_D7987F'
                        )
                      }}
                      <textarea
                        v-model="q.text"
                        rows="2"
                        maxlength="1000"
                      />
                    </label>
                    <div :class="surveyClasses('sv-two')">
                      <label>
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.CODIGO_F58B85')
                        }}
                        <input
                          v-model="q.key"
                          maxlength="60"
                        />
                      </label>
                      <label :class="surveyClasses('sv-check-row')">
                        <input
                          v-model="q.required"
                          type="checkbox"
                          :disabled="i === 0"
                        />
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RESPOSTA_OBRIGATORIA_17BDCC'
                          )
                        }}
                      </label>
                    </div>
                    <div
                      v-if="q.type === 'scale'"
                      :class="surveyClasses('sv-two')"
                    >
                      <label>
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.MINIMO_5D61B4')
                        }}
                        <input
                          v-model.number="q.min"
                          type="number"
                          min="0"
                          max="99"
                          :disabled="i === 0 && model.kind === 'nps'"
                        />
                      </label>
                      <label>
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.MAXIMO_994D51')
                        }}
                        <input
                          v-model.number="q.max"
                          type="number"
                          min="1"
                          max="100"
                          :disabled="i === 0 && model.kind === 'nps'"
                        />
                      </label>
                    </div>
                    <template v-if="q.type === 'choice'">
                      <div
                        v-for="(option, j) in q.options"
                        :key="j"
                        :class="surveyClasses('sv-option-row')"
                      >
                        <input
                          v-model="option.label"
                          :aria-label="`Texto da opção ${j + 1}`"
                          maxlength="120"
                        />
                        <button
                          type="button"
                          :class="surveyClasses('sv-icon-button')"
                          :aria-label="`Remover opção ${j + 1}`"
                          @click="q.options.splice(j, 1)"
                        >
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_8DB71E'
                            )
                          }}
                        </button>
                      </div>
                      <button
                        type="button"
                        :class="surveyClasses('sv-text-button')"
                        @click="addOption(q)"
                      >
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ADICIONAR_OPCAO_C3C3E2'
                          )
                        }}
                      </button>
                    </template>
                    <details
                      v-if="i > 0"
                      :class="surveyClasses('sv-advanced')"
                    >
                      <summary>
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CONDICAO_DE_EXIBICAO_OPCIONAL_2FE6BD'
                          )
                        }}
                      </summary>
                      <label>
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PERGUNTA_ANTERIOR_EC385A'
                          )
                        }}
                        <select
                          :value="q.condition?.question || ''"
                          @change="chooseCondition(q, $event)"
                        >
                          <option value="">
                            {{
                              $t(
                                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SEMPRE_EXIBIR_12A608'
                              )
                            }}
                          </option>
                          <option
                            v-for="prior in model.questions.slice(0, i)"
                            :key="prior.key"
                            :value="prior.key"
                          >
                            {{ prior.text }}
                          </option>
                        </select>
                      </label>
                      <div
                        v-if="q.condition"
                        :class="surveyClasses('sv-two')"
                      >
                        <label>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CONDICAO_C36216'
                            )
                          }}
                          <select v-model="q.condition.operator">
                            <option value="eq">
                              {{
                                $t(
                                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.IGUAL_A_F6C2AE'
                                )
                              }}
                            </option>
                            <option value="lte">
                              {{
                                $t(
                                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.MENOR_OU_IGUAL_A_4B2F4E'
                                )
                              }}
                            </option>
                            <option value="gte">
                              {{
                                $t(
                                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.MAIOR_OU_IGUAL_A_A12451'
                                )
                              }}
                            </option>
                          </select>
                        </label>
                        <label>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RESPOSTA_CODIGO_DA_OPCAO_D5C28D'
                            )
                          }}
                          <input v-model="q.condition.value" />
                        </label>
                      </div>
                    </details>
                  </div>
                </article>
                <label v-if="model.kind === 'ces'">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.DIRECAO_DA_ESCALA_CES_9389DD'
                    )
                  }}
                  <select v-model="model.settings.ces_direction">
                    <option value="higher_is_better">
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NOTA_MAIOR_SIGNIFICA_MELHOR_EXPERIENCIA_794C21'
                        )
                      }}
                    </option>
                    <option value="lower_is_better">
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NOTA_MENOR_SIGNIFICA_MELHOR_EXPERIENCIA_2CF53D'
                        )
                      }}
                    </option>
                  </select>
                </label>
                <details
                  v-if="model.kind !== 'nps'"
                  :class="surveyClasses('sv-advanced')"
                >
                  <summary>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CLASSIFICACAO_DE_BAIXA_AVALIACAO_OPCIONAL_601261'
                      )
                    }}
                  </summary>
                  <label>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.LIMITE_NA_ESCALA_ORIGINAL_2EBD00'
                      )
                    }}
                    <input
                      :value="model.settings.low_threshold ?? ''"
                      type="number"
                      :min="model.questions[0].min"
                      :max="model.questions[0].max"
                      @input="thresholdInput"
                    />
                  </label>
                  <p>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SEM_LIMITE_DEFINIDO_NAO_CLASSIFICAMOS_2176ED'
                      )
                    }}
                  </p>
                </details>
                <label>
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.MENSAGEM_DE_AGRADECIMENTO_60821B'
                    )
                  }}
                  <input
                    v-model="model.settings.thank_you"
                    maxlength="1000"
                  />
                </label>
                <p :class="surveyClasses('sv-help')">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ESCALAS_CSATCES_SAO_NORMALIZADAS_NOS_377284'
                    )
                  }}
                </p>
              </div>
              <div
                v-if="step === 2"
                :class="surveyClasses('sv-fields')"
              >
                <article
                  v-for="c in channels"
                  :key="c.key"
                  :class="surveyClasses(['sv-channel-card', c.tone])"
                >
                  <header>
                    <span :class="surveyClasses('sv-channel-icon')">
                      <span :class="c.icon" />
                    </span>
                    <div>
                      <h4>{{ c.label }}</h4>
                      <p>{{ c.hint }}</p>
                    </div>
                    <input
                      v-model="model.channels[c.key].enabled"
                      type="checkbox"
                      role="switch"
                      :aria-label="`Habilitar ${c.label}`"
                    />
                  </header>
                  <div :class="surveyClasses('sv-channel-foot')">
                    <span>
                      {{
                        model.channels[c.key].enabled
                          ? 'Habilitado no rascunho'
                          : 'Desabilitado — não gera envio'
                      }}
                    </span>
                    <button
                      type="button"
                      :class="surveyClasses('sv-button')"
                      :disabled="!model.channels[c.key].enabled"
                      @click="
                        expandedChannel = expandedChannel === c.key ? '' : c.key
                      "
                    >
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CONFIGURAR_D685DD'
                        )
                      }}
                    </button>
                  </div>
                  <div
                    v-if="
                      expandedChannel === c.key && model.channels[c.key].enabled
                    "
                    :class="surveyClasses('sv-channel-config')"
                  >
                    <template v-if="c.key !== 'public_link'">
                      <label>
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CAIXA_IDENTIDADE_AUTORIZADA_F9918B'
                          )
                        }}
                        <select v-model="model.channels[c.key].inbox_id">
                          <option :value="null">
                            {{
                              $t(
                                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SELECIONE_A_CAIXA_D9AF65'
                              )
                            }}
                          </option>
                          <option
                            v-for="inbox in inboxes(c.key)"
                            :key="inbox.id"
                            :value="inbox.id"
                          >
                            {{ inbox.name }}
                          </option>
                        </select>
                      </label>
                      <p
                        v-if="!inboxes(c.key).length"
                        :class="surveyClasses('sv-help')"
                      >
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NENHUMA_CAIXA_DISPONIVEL_NO_SEU_62D166'
                          )
                        }}
                      </p>
                      <label>
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.MENSAGEM_COM_LINK_67CA47'
                          )
                        }}
                        <textarea
                          v-model="model.channels[c.key].message"
                          rows="3"
                          maxlength="4000"
                        />
                      </label>
                      <small>
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.VARIAVEL_OBRIGATORIA_A7313C'
                          )
                        }}
                        <code>{{ surveyLinkMarker }}</code>
                      </small>
                      <details
                        v-if="c.key === 'whatsapp'"
                        :class="surveyClasses('sv-advanced')"
                      >
                        <summary>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TEMPLATE_APROVADO_PARA_FORA_DA_A7A38C'
                            )
                          }}
                        </summary>
                        <SurveyRuleTemplatePanel
                          v-model="model.channels.whatsapp.whatsapp_template"
                          :inbox-id="model.channels.whatsapp.inbox_id"
                          :executor-id="model.rules.execution_member_id"
                          :inboxes="templateInboxes"
                        />
                        <small>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SEM_TEMPLATE_APROVADO_O_ENVIO_D1E5B9'
                            )
                          }}
                        </small>
                      </details>
                    </template>
                    <p v-else>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.O_LINK_FICA_DISPONIVEL_PARA_A39883'
                        )
                      }}
                    </p>
                  </div>
                </article>
                <article
                  :class="surveyClasses('sv-channel-card pink sv-unavailable')"
                >
                  <header>
                    <span :class="surveyClasses('sv-channel-icon')">
                      <span class="i-lucide-phone" />
                    </span>
                    <div>
                      <h4>
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SMS_URA_03E150'
                          )
                        }}
                      </h4>
                      <p>
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.INTEGRACAO_DE_ENTREGA_NAO_DISPONIVEL_9ACCD0'
                          )
                        }}
                      </p>
                    </div>
                    <input
                      type="checkbox"
                      disabled
                      :aria-label="
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SMS_E_URA_INDISPONIVEIS_63D006'
                        )
                      "
                    />
                  </header>
                  <div :class="surveyClasses('sv-channel-foot')">
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NAO_SERA_PUBLICADO_NEM_USADO_B103CC'
                      )
                    }}
                  </div>
                </article>
                <p :class="surveyClasses('sv-help')">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.HABILITAR_UM_CANAL_NAO_SUBSTITUI_4CF945'
                    )
                  }}
                </p>
              </div>
              <div
                v-if="step === 3"
                :class="surveyClasses('sv-fields')"
              >
                <div :class="surveyClasses('sv-tinted blue')">
                  <h4>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.QUANDO_AVALIAR_O_ENVIO_83F4E2'
                      )
                    }}
                  </h4>
                  <label :class="surveyClasses('sv-radio-row')">
                    <input
                      v-model="model.rules.event"
                      type="radio"
                      value="closed"
                    />
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.APOS_O_ENCERRAMENTO_DO_CHAMADO_0DDAB3'
                      )
                    }}
                  </label>
                  <label :class="surveyClasses('sv-radio-row')">
                    <input
                      v-model="model.rules.event"
                      type="radio"
                      value="first_agent_response"
                    />
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.APOS_A_PRIMEIRA_RESPOSTA_PUBLICA_591E58'
                      )
                    }}
                  </label>
                  <label :class="surveyClasses('sv-radio-row')">
                    <input
                      v-model="model.rules.event"
                      type="radio"
                      value="manual"
                    />
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ENVIO_MANUAL_POR_USUARIO_AUTORIZADO_F967BE'
                      )
                    }}
                  </label>
                  <p :class="surveyClasses('sv-help')">
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PRIMEIRA_RESPOSTA_SIGNIFICA_A_RESPOSTA_006533'
                      )
                    }}
                  </p>
                  <label>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.AGUARDAR_APOS_O_EVENTO_MINUTOS_0A4DBB'
                      )
                    }}
                    <input
                      v-model.number="model.rules.delay_minutes"
                      type="number"
                      min="0"
                      max="52560"
                    />
                  </label>
                </div>
                <div :class="surveyClasses('sv-two')">
                  <label>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TIPO_DE_CHAMADO_C1ADAF'
                      )
                    }}
                    <select v-model="model.rules.ticket_type_id">
                      <option :value="null">
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TODOS_OS_TIPOS_88BFB9'
                          )
                        }}
                      </option>
                      <option
                        v-for="row in options.ticket_types"
                        :key="row.id"
                        :value="row.id"
                      >
                        {{ row.name }}
                      </option>
                    </select>
                  </label>
                  <label>
                    {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.FILA_56CB74') }}
                    <select v-model="model.rules.queue_id">
                      <option :value="null">
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TODAS_AS_FILAS_2474BB'
                          )
                        }}
                      </option>
                      <option
                        v-for="row in options.queues"
                        :key="row.id"
                        :value="row.id"
                      >
                        {{ row.name }}
                      </option>
                    </select>
                  </label>
                  <label>
                    {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.EQUIPE_DE0F23') }}
                    <select v-model="model.rules.team_id">
                      <option :value="null">
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TODAS_AS_EQUIPES_5E2AFE'
                          )
                        }}
                      </option>
                      <option
                        v-for="row in options.teams"
                        :key="row.id"
                        :value="row.id"
                      >
                        {{ row.name }}
                      </option>
                    </select>
                  </label>
                  <label>
                    {{
                      $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PRIORIDADE_F61577')
                    }}
                    <select v-model="model.rules.priority_id">
                      <option :value="null">
                        {{
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.TODAS_AS_PRIORIDADES_AC72A1'
                          )
                        }}
                      </option>
                      <option
                        v-for="row in options.priorities"
                        :key="row.id"
                        :value="row.id"
                      >
                        {{ row.name }}
                      </option>
                    </select>
                  </label>
                </div>
                <label>
                  <span>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EXECUTOR_AUTORIZADO_DA_REGRA_3954B1'
                      )
                    }}
                    <b :class="surveyClasses('sv-required')">
                      {{
                        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_684888')
                      }}
                    </b>
                  </span>
                  <select v-model="model.rules.execution_member_id">
                    <option :value="null">
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SELECIONE_O_EXECUTOR_7BD614'
                        )
                      }}
                    </option>
                    <option
                      v-for="row in options.executors"
                      :key="row.id"
                      :value="row.id"
                    >
                      {{ row.name }}
                    </option>
                  </select>
                  <small>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.IDENTIDADE_QUE_AUTORIZA_AS_CONSULTAS_653FA9'
                      )
                    }}
                  </small>
                </label>
                <div :class="surveyClasses('sv-two')">
                  <label>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.INTERVALO_MINIMO_POR_CLIENTE_E_425A31'
                      )
                    }}
                    <input
                      v-model.number="model.rules.frequency_days"
                      type="number"
                      min="0"
                      max="3650"
                    />
                    <small>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ZERO_DESATIVA_APENAS_ESSE_LIMITE_27E9EA'
                        )
                      }}
                    </small>
                  </label>
                  <label>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.VALIDADE_DA_RESPOSTA_HORAS_32D068'
                      )
                    }}
                    <input
                      v-model.number="model.rules.expires_hours"
                      type="number"
                      min="1"
                      max="8760"
                    />
                  </label>
                </div>
                <label :class="surveyClasses('sv-check-row')">
                  <input
                    v-model="model.rules.consent_required"
                    type="checkbox"
                    disabled
                  />
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EXIGIR_CONSENTIMENTO_AUTORIZADO_DO_DESTINATARIO_F7FA4D'
                    )
                  }}
                </label>
                <div :class="surveyClasses('sv-tinted amber')">
                  <label :class="surveyClasses('sv-check-row')">
                    <input
                      v-model="model.rules.send_window.enabled"
                      type="checkbox"
                      role="switch"
                    />
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RESTRINGIR_DIAS_E_HORARIOS_DE_9F0818'
                      )
                    }}
                  </label>
                  <template v-if="model.rules.send_window.enabled">
                    <div :class="surveyClasses('sv-day-grid')">
                      <button
                        v-for="(day, i) in days"
                        :key="day"
                        type="button"
                        :aria-pressed="model.rules.send_window.days.includes(i)"
                        :class="{
                          selected: model.rules.send_window.days.includes(i),
                        }"
                        @click="toggleDay(i)"
                      >
                        {{ day }}
                      </button>
                    </div>
                    <div :class="surveyClasses('sv-two')">
                      <label>
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.INICIO_325DFC')
                        }}
                        <input
                          v-model="model.rules.send_window.start"
                          type="time"
                        />
                      </label>
                      <label>
                        {{
                          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.FIM_672FF2')
                        }}
                        <input
                          v-model="model.rules.send_window.end"
                          type="time"
                        />
                      </label>
                    </div>
                    <label>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.FUSO_HORARIO_E87F8D'
                        )
                      }}
                      <input
                        v-model="model.rules.send_window.timezone"
                        :placeholder="
                          $t(
                            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.AMERICASAOPAULO_53E24A'
                          )
                        "
                      />
                    </label>
                    <small>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.FORA_DA_JANELA_O_ENVIO_A06335'
                        )
                      }}
                    </small>
                  </template>
                </div>
                <details :class="surveyClasses('sv-advanced')">
                  <summary>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PREFERENCIA_DE_CANAL_E_PRIORIDADE_0EF030'
                      )
                    }}
                  </summary>
                  <p :class="surveyClasses('sv-help')">
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.O_MOTOR_ESCOLHE_UM_CANAL_E0DB54'
                      )
                    }}
                  </p>
                  <div
                    v-for="(c, i) in model.rules.channel_order"
                    :key="c"
                    :class="surveyClasses('sv-channel-order')"
                  >
                    <span>
                      {{ i + 1
                      }}{{
                        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_CDB4EE')
                      }}
                      {{ channelLabel(c)
                      }}{{ model.channels[c].enabled ? '' : ' (desabilitado)' }}
                    </span>
                    <button
                      type="button"
                      :disabled="i === 0"
                      :aria-label="`Priorizar ${channelLabel(c)}`"
                      @click="moveChannel(i, -1)"
                    >
                      {{
                        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_D2E966')
                      }}
                    </button>
                    <button
                      type="button"
                      :disabled="i === 2"
                      :aria-label="`Reduzir prioridade de ${channelLabel(c)}`"
                      @click="moveChannel(i, 1)"
                    >
                      {{
                        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_07A2AB')
                      }}
                    </button>
                  </div>
                  <label>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PRIORIDADE_DA_REGRA_0_A_07632A'
                      )
                    }}
                    <input
                      v-model.number="model.rules.priority"
                      type="number"
                      min="0"
                      max="1000"
                    />
                  </label>
                </details>
                <div
                  v-if="!options.automation_enabled"
                  :class="surveyClasses('sv-alert sv-alert-warning')"
                >
                  {{ $t('JRC_SERVICE_DESK.COORDINATED.survey_off_help') }}
                </div>
              </div>
              <div
                v-if="step === 4"
                :class="surveyClasses('sv-fields')"
              >
                <div :class="surveyClasses('sv-tinted purple')">
                  <h4>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EQUIPES_AUTORIZADAS_5AAD80'
                      )
                    }}
                  </h4>
                  <p>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SEM_SELECAO_ADICIONAL_VALEM_AS_04D6EB'
                      )
                    }}
                  </p>
                  <div :class="surveyClasses('sv-team-choices')">
                    <label
                      v-for="team in options.teams"
                      :key="team.id"
                      :class="surveyClasses('sv-check-row')"
                    >
                      <input
                        v-model="model.permissions.team_ids"
                        type="checkbox"
                        :value="team.id"
                        :disabled="!permissions.manage_permissions"
                      />
                      {{ team.name }}
                    </label>
                  </div>
                </div>
                <div :class="surveyClasses('sv-permissions-table')">
                  <table>
                    <thead>
                      <tr>
                        <th>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PERFIL_00D551'
                            )
                          }}
                        </th>
                        <th>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EDITAR_2EBA94'
                            )
                          }}
                        </th>
                        <th>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PUBLICAR_326FDF'
                            )
                          }}
                        </th>
                        <th>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RESPOSTAS_5B1903'
                            )
                          }}
                        </th>
                        <th>
                          {{
                            $t(
                              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RELATORIOS_DC4BB1'
                            )
                          }}
                        </th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        v-for="role in roles"
                        :key="role.key"
                      >
                        <th>{{ role.label }}</th>
                        <td
                          v-for="permission in [
                            'edit_roles',
                            'publish_roles',
                            'response_roles',
                            'report_roles',
                          ]"
                          :key="permission"
                          :data-label="permissionLabel(permission)"
                        >
                          <input
                            v-model="model.permissions[permission]"
                            type="checkbox"
                            :value="role.key"
                            :disabled="
                              role.key === 'administrator' ||
                              !permissions.manage_permissions
                            "
                            :aria-label="`${role.label}: ${permissionLabel(permission)}`"
                          />
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <p :class="surveyClasses('sv-help')">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EDITAR_E_PUBLICAR_TAMBEM_EXIGEM_FDE978'
                    )
                  }}
                </p>
                <label :class="surveyClasses('sv-check-row')">
                  <input
                    v-model="model.permissions.customer_own_response"
                    type="checkbox"
                    :disabled="!permissions.manage_permissions"
                  />
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CLIENTE_PODE_CONSULTAR_A_PROPRIA_A9E898'
                    )
                  }}
                </label>
                <h4>
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.COMPARTILHAMENTO_DOS_RESULTADOS_B874CB'
                    )
                  }}
                </h4>
                <div :class="surveyClasses('sv-two')">
                  <label :class="surveyClasses('sv-sharing-card blue')">
                    <input
                      v-model="model.permissions.share_relationship"
                      type="checkbox"
                      role="switch"
                      :disabled="!permissions.manage_permissions"
                    />
                    <strong>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RELACIONAMENTO_E0FB5A'
                        )
                      }}
                    </strong>
                    <small>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.DISPONIBILIZAR_NAS_VISOES_AUTORIZADAS_E_0FE869'
                        )
                      }}
                    </small>
                  </label>
                  <label :class="surveyClasses('sv-sharing-card green')">
                    <input
                      v-model="model.permissions.share_reports"
                      type="checkbox"
                      role="switch"
                      :disabled="!permissions.manage_permissions"
                    />
                    <strong>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RELATORIOS_DC4BB1'
                        )
                      }}
                    </strong>
                    <small>
                      {{
                        $t(
                          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PERMITIR_AGREGACOES_E_EXPORTACOES_AUTORIZADAS_029009'
                        )
                      }}
                    </small>
                  </label>
                </div>
                <div :class="surveyClasses('sv-alert sv-alert-info')">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.AS_RESPOSTAS_PERMANECEM_VINCULADAS_AO_46AC0D'
                    )
                  }}
                </div>
              </div>
              <div
                v-if="step === 5"
                :class="surveyClasses('sv-fields')"
              >
                <article
                  v-for="(item, i) in summary"
                  :key="item.title"
                  :class="surveyClasses('sv-review-card')"
                >
                  <span :class="surveyClasses(['sv-section-icon', item.tone])">
                    <span :class="item.icon" />
                  </span>
                  <div>
                    <h4>{{ item.title }}</h4>
                    <p>{{ item.detail || 'Não configurado' }}</p>
                  </div>
                  <button
                    type="button"
                    :class="surveyClasses('sv-text-button')"
                    @click="go(i)"
                  >
                    {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.EDITAR_2EBA94') }}
                  </button>
                </article>
                <label :class="surveyClasses('sv-sharing-card purple')">
                  <input
                    v-model="model.active"
                    :disabled="!permissions.edit"
                    type="checkbox"
                    role="switch"
                  />
                  <strong>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PUBLICAR_COMO_PESQUISA_ATIVA_B6AD0F'
                      )
                    }}
                  </strong>
                  <small>
                    {{
                      $t(
                        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.A_ATIVACAO_VALE_APOS_A_A477CE'
                      )
                    }}
                  </small>
                </label>
                <label :class="surveyClasses('sv-check-row')">
                  <input
                    v-model="confirmPublication"
                    type="checkbox"
                  />
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CONFERI_AS_ETAPAS_E_AUTORIZO_B336AF'
                    )
                  }}
                </label>
                <div :class="surveyClasses('sv-alert sv-alert-info')">
                  {{
                    $t(
                      'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PUBLICAR_NAO_ENVIA_MENSAGENS_NEM_E68FE5'
                    )
                  }}
                </div>
              </div>
            </fieldset>
            <SurveyModelPreview :model="model" />
          </div>
        </div>
        <footer :class="surveyClasses('sv-modal-footer')">
          <div>
            <button
              type="button"
              :class="surveyClasses('sv-button')"
              :disabled="busy"
              @click="close"
            >
              {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.CANCELAR_BB9DBB') }}
            </button>
            <button
              v-if="step > 0"
              type="button"
              :class="surveyClasses('sv-button')"
              :disabled="busy || operationUnknown"
              @click="go(step - 1)"
            >
              {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.VOLTAR_30A660') }}
            </button>
          </div>
          <div>
            <span :class="surveyClasses('sv-draft-status')">
              {{
                busy
                  ? 'Confirmando no servidor...'
                  : dirty
                    ? 'Alterações não salvas'
                    : modelId
                      ? 'Rascunho salvo'
                      : 'Novo rascunho'
              }}
            </span>
            <button
              type="button"
              :class="surveyClasses('sv-button')"
              :disabled="busy || operationUnknown || !permissions.edit"
              @click="save(false)"
            >
              {{
                $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SALVAR_RASCUNHO_BB2CC1')
              }}
            </button>
            <button
              v-if="step < 5"
              type="button"
              :class="surveyClasses('sv-button sv-primary')"
              :disabled="busy || operationUnknown"
              @click="go(step + 1)"
            >
              {{
                $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PROXIMA_ETAPA_A551D0')
              }}
            </button>
            <button
              v-else
              type="button"
              :class="surveyClasses('sv-button sv-primary')"
              :disabled="
                busy ||
                operationUnknown ||
                !permissions.publish ||
                !confirmPublication
              "
              @click="publish"
            >
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PUBLICAR_PESQUISA_4BE3A1'
                )
              }}
            </button>
          </div>
        </footer>
        <div
          v-if="leavePrompt"
          :class="surveyClasses('sv-leave')"
        >
          <section
            role="alertdialog"
            aria-labelledby="sv-leave-title"
          >
            <h3 id="sv-leave-title">
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EXISTEM_ALTERACOES_NAO_CONFIRMADAS_24A7A1'
                )
              }}
            </h3>
            <p>
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.O_QUE_JA_FOI_SALVO_0DA88C'
                )
              }}
            </p>
            <div>
              <button
                type="button"
                :class="surveyClasses('sv-button')"
                @click="leavePrompt = false"
              >
                {{
                  $t(
                    'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CONTINUAR_EDITANDO_A226AA'
                  )
                }}
              </button>
              <button
                type="button"
                :class="surveyClasses('sv-button')"
                @click="discard"
              >
                {{
                  $t(
                    'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SAIR_SEM_SALVAR_00488D'
                  )
                }}
              </button>
              <button
                type="button"
                :class="surveyClasses('sv-button sv-primary')"
                :disabled="busy || operationUnknown"
                @click="save(true)"
              >
                {{
                  $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SALVAR_E_SAIR_0C08CF')
                }}
              </button>
            </div>
          </section>
        </div>
      </section>
    </div>
  </Teleport>
</template>
