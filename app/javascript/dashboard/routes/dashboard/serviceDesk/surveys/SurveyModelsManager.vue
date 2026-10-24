<script setup>
import { surveyClasses } from './surveyClasses';
import { reactive, toRefs, computed, onBeforeUnmount, watch } from 'vue';
import SurveyModelsAPI from 'dashboard/api/serviceDeskSurveyModels';
import SurveyModelWizard from './SurveyModelWizard.vue';
import { messageErrors } from './modelForm';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
  unit: { type: Object, required: true },
  api: { type: Object, default: () => SurveyModelsAPI },
});
defineOptions({ name: 'SurveyModelsManager' });
const state = reactive(
  (() => {
    return {
      rows: [],
      options: null,
      page: 1,
      total: 0,
      busy: false,
      error: '',
      notice: '',
      editorOpen: false,
      editing: null,
      pendingAction: null,
      history: null,
      ticketId: '',
      controller: null,
      revision: 0,
      alive: true,
    };
  })()
);
const {
  rows,
  options,
  page,
  total,
  busy,
  error,
  notice,
  editorOpen,
  editing,
  pendingAction,
  history,
  ticketId,
} = toRefs(state);

const identity = computed(() => {
  return `${props.accountId}:${props.unit.id}`;
});
async function load() {
  state.revision += 1;
  const requestRevision = state.revision;
  state.controller?.abort();
  state.controller = new AbortController();
  state.busy = true;
  state.error = '';
  state.rows = [];
  state.options = null;
  try {
    const [choices, list] = await Promise.all([
      props.api.options(props.accountId, props.unit.id, {
        signal: state.controller.signal,
      }),
      props.api.list(props.accountId, props.unit.id, state.page, {
        signal: state.controller.signal,
      }),
    ]);
    if (!state.alive || requestRevision !== state.revision) return;
    state.options = choices.data;
    state.rows = list.data.payload;
    state.total = list.data.meta.total;
  } catch (e) {
    if (
      state.alive &&
      requestRevision === state.revision &&
      e.code !== 'ERR_CANCELED'
    )
      state.error = messageErrors(e)
        .map(r => r.message)
        .join(' ');
  } finally {
    if (state.alive && requestRevision === state.revision) state.busy = false;
  }
}
function create() {
  state.editing = null;
  state.editorOpen = true;
}
async function edit(row) {
  if (state.busy) return;
  state.busy = true;
  const requestIdentity = identity.value;
  try {
    const response = await props.api.get(props.accountId, row.id);
    if (state.alive && requestIdentity === identity.value) {
      state.editing = response.data;
      state.editorOpen = true;
    }
  } catch (e) {
    if (state.alive && requestIdentity === identity.value)
      state.error = messageErrors(e)
        .map(r => r.message)
        .join(' ');
  } finally {
    if (state.alive && requestIdentity === identity.value) state.busy = false;
  }
}
function changed(row) {
  const index = state.rows.findIndex(r => r.id === row.id);
  if (index >= 0) state.rows.splice(index, 1, row);
  else state.rows.unshift(row);
}
async function closeEditor() {
  state.editorOpen = false;
  state.editing = null;
  await load();
}
function confirm(type, row) {
  state.pendingAction = { type, row };
  state.ticketId = '';
  state.error = '';
}
function stateLabel(value) {
  return (
    {
      enqueued: 'enfileirada',
      scheduled: 'agendada',
      suppressed: 'suprimida',
      blocked: 'bloqueada',
      created: 'criada',
      existing: 'já existente',
      disabled: 'desabilitada',
      failed: 'falhou',
    }[value] ||
    value ||
    'não informado'
  );
}
function reasonLabel(value) {
  return (
    {
      automation_disabled: 'automação desligada',
      no_matching_rule: 'nenhuma regra aplicável',
      no_eligible_channel: 'nenhum canal elegível',
      consent_missing: 'consentimento ausente',
      frequency_limit: 'limite de frequência',
      source_not_completed: 'origem ainda não concluída',
    }[value] || value
  );
}
async function execute() {
  if (!state.pendingAction || state.busy) return;
  const action = state.pendingAction;
  const requestIdentity = identity.value;
  state.busy = true;
  state.error = '';
  state.notice = '';
  try {
    let result;
    if (action.type === 'duplicate')
      result = await props.api.duplicate(props.accountId, action.row.id);
    else if (action.type === 'deactivate') {
      await props.api.deactivate(
        props.accountId,
        action.row.id,
        action.row.lock_version
      );
      const check = await props.api.get(props.accountId, action.row.id);
      if (check.data.active) throw new Error('Unconfirmed');
    } else if (action.type === 'dispatch') {
      result = await props.api.dispatch(
        props.accountId,
        action.row.id,
        state.ticketId
      );
    }
    if (!state.alive || requestIdentity !== identity.value) return;
    state.pendingAction = null;
    if (action.type === 'duplicate') {
      state.editing = result.data;
      state.editorOpen = true;
    } else if (action.type === 'dispatch') {
      state.notice = `Solicitação avaliada pelo motor. Estado: ${stateLabel(result.data.state)}. ${result.data.reason ? 'Motivo: ' + reasonLabel(result.data.reason) + '.' : ''} A entrega depende do provedor e dos recibos.`;
    } else {
      state.notice =
        'Modelo desativado e relido. Respostas históricas preservadas.';
      await load();
    }
  } catch (e) {
    if (state.alive && requestIdentity === identity.value) {
      state.error = messageErrors(e)
        .map(r => r.message)
        .join(' ');
      if (!e.response || e.response.status >= 500) {
        state.pendingAction = null;
        state.notice =
          'Resultado incerto: atualize a lista antes de repetir. A duplicação não deve ser repetida automaticamente.';
      }
    }
  } finally {
    if (state.alive && requestIdentity === identity.value) state.busy = false;
  }
}
async function versions(row) {
  const requestIdentity = identity.value;
  state.busy = true;
  state.error = '';
  try {
    const response = await props.api.history(props.accountId, row.id);
    if (state.alive && requestIdentity === identity.value)
      state.history = { name: row.payload.name, rows: response.data.payload };
  } catch (e) {
    if (state.alive && requestIdentity === identity.value)
      state.error = messageErrors(e)
        .map(r => r.message)
        .join(' ');
  } finally {
    if (state.alive && requestIdentity === identity.value) state.busy = false;
  }
}
function date(value) {
  return value
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : '—';
}
async function navigate(delta) {
  state.page += delta;
  await load();
}

onBeforeUnmount(() => {
  state.alive = false;
  state.revision += 1;
  state.controller?.abort();
});
watch(
  identity,
  () => {
    state.page = 1;
    state.editorOpen = false;
    state.editing = null;
    state.pendingAction = null;
    state.history = null;
    load();
  },
  { immediate: true }
);
defineExpose({
  ...toRefs(state),
  identity,
  load,
  create,
  edit,
  changed,
  closeEditor,
  confirm,
  execute,
  stateLabel,
  reasonLabel,
  versions,
  date,
  navigate,
});
</script>

<template>
  <section
    :class="surveyClasses('sv-manager')"
    aria-labelledby="sv-models-title"
  >
    <header :class="surveyClasses('sv-manager-header')">
      <div>
        <span :class="surveyClasses('sv-eyebrow')">
          {{
            $t(
              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SERVICE_DESK_PESQUISAS_DE_SATISFACAO_605D0E'
            )
          }}
        </span>
        <h2 id="sv-models-title">
          {{
            $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.MODELOS_DE_PESQUISA_7678A4')
          }}
        </h2>
        <p>
          {{
            $t(
              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CONFIGURE_A_EXPERIENCIA_DE_AVALIACAO_D879A4'
            )
          }}
          <strong>{{ unit.name }}</strong>
          {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_CDB4EE') }}
        </p>
      </div>
      <button
        v-if="options?.can_create"
        type="button"
        :class="surveyClasses('sv-button sv-primary')"
        :disabled="busy"
        @click="create"
      >
        {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.NOVO_MODELO_99B6DC') }}
      </button>
    </header>
    <div
      v-if="error"
      :class="surveyClasses('sv-alert sv-alert-error')"
      role="alert"
    >
      {{ error }}
      <button
        type="button"
        :class="surveyClasses('sv-text-button')"
        :disabled="busy"
        @click="load"
      >
        {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.ATUALIZAR_CONSULTA_996A29') }}
      </button>
    </div>
    <p
      v-if="notice"
      :class="surveyClasses('sv-alert sv-alert-info')"
      role="status"
    >
      {{ notice }}
    </p>
    <div
      v-if="busy && !options"
      :class="surveyClasses('sv-empty')"
      role="status"
    >
      {{
        $t(
          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CARREGANDO_MODELOS_AUTORIZADOS_2790CC'
        )
      }}
    </div>
    <template v-else-if="options">
      <div :class="surveyClasses('sv-stat-row')">
        <article :class="surveyClasses('sv-tinted purple')">
          <strong>{{ total }}</strong>
          <span>
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.MODELOS_NO_SEU_ESCOPO_4E11D4'
              )
            }}
          </span>
        </article>
        <article :class="surveyClasses('sv-tinted blue')">
          <strong>
            {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.6_ETAPAS_A75690') }}
          </strong>
          <span>
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.UM_CADASTRO_COMPLETO_F4E4E5'
              )
            }}
          </span>
        </article>
        <article :class="surveyClasses('sv-tinted green')">
          <strong>
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.VERSOES_PRESERVADAS_C7127A'
              )
            }}
          </strong>
          <span>
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PUBLICAR_NAO_ENVIA_MENSAGENS_431705'
              )
            }}
          </span>
        </article>
      </div>
      <p
        v-if="!options.automation_enabled"
        :class="surveyClasses('sv-alert sv-alert-warning')"
      >
        {{
          $t(
            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.A_AUTOMACAO_DE_PESQUISAS_ESTA_A07D56'
          )
        }}
      </p>
      <div
        v-if="!rows.length"
        :class="surveyClasses('sv-empty')"
      >
        <span :class="surveyClasses('sv-empty-icon')">
          {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_B7927B') }}
        </span>
        <h3>
          {{
            $t(
              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NENHUM_MODELO_AUTORIZADO_NESTA_UNIDADE_D07067'
            )
          }}
        </h3>
        <p>
          {{
            $t(
              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CRIE_UM_MODELO_DE_NPS_2410BC'
            )
          }}
        </p>
        <button
          v-if="options.can_create"
          type="button"
          :class="surveyClasses('sv-button sv-primary')"
          @click="create"
        >
          {{
            $t(
              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.CRIAR_PRIMEIRO_MODELO_DB3529'
            )
          }}
        </button>
      </div>
      <div
        v-else
        :class="surveyClasses('sv-model-grid')"
      >
        <article
          v-for="row in rows"
          :key="row.id"
          :class="surveyClasses('sv-model-card')"
        >
          <header>
            <span :class="surveyClasses(['sv-kind-badge', row.payload.kind])">
              {{ row.payload.kind?.toUpperCase() }}
            </span>
            <span
              :class="
                surveyClasses([
                  'sv-status',
                  row.active ? 'green' : row.published_at ? 'amber' : 'blue',
                ])
              "
            >
              {{
                row.active
                  ? 'Publicada e ativa'
                  : row.published_at
                    ? 'Desativada'
                    : 'Rascunho'
              }}
            </span>
          </header>
          <h3>{{ row.payload.name || 'Modelo sem nome' }}</h3>
          <p>{{ row.payload.description || 'Sem descrição' }}</p>
          <div :class="surveyClasses('sv-model-meta')">
            <span>
              {{ row.payload.questions?.length || 0 }}
              {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PERGUNTAS_62682F') }}
            </span>
            <span>
              {{
                row.published_version
                  ? `Versão ${row.published_version}`
                  : 'Ainda não publicado'
              }}
            </span>
            <span v-if="row.changed && row.published_at">
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.HA_ALTERACOES_EM_RASCUNHO_E658D0'
                )
              }}
            </span>
            <small>{{ row.code }}</small>
          </div>
          <footer>
            <button
              type="button"
              :class="surveyClasses('sv-button')"
              :disabled="busy"
              @click="edit(row)"
            >
              {{ row.permissions.edit ? 'Editar' : 'Visualizar' }}
            </button>
            <button
              v-if="row.permissions.duplicate"
              type="button"
              :class="surveyClasses('sv-text-button')"
              :disabled="busy"
              @click="confirm('duplicate', row)"
            >
              {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.DUPLICAR_88F772') }}
            </button>
            <details>
              <summary>
                {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.MAIS_ACOES_85E1F8') }}
              </summary>
              <button
                v-if="row.definition_id"
                type="button"
                @click="versions(row)"
              >
                {{
                  $t(
                    'RELATIONSHIP.SURVEY_MODELS_V3.COPY.VERSOES_PUBLICADAS_53FBEE'
                  )
                }}
              </button>
              <button
                v-if="row.active && row.permissions.publish"
                type="button"
                @click="confirm('deactivate', row)"
              >
                {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.DESATIVAR_67AFBE') }}
              </button>
              <button
                v-if="
                  row.active &&
                  row.payload.rules?.event === 'manual' &&
                  !row.changed
                "
                type="button"
                @click="confirm('dispatch', row)"
              >
                {{
                  $t(
                    'RELATIONSHIP.SURVEY_MODELS_V3.COPY.AVALIAR_ENVIO_MANUAL_D50103'
                  )
                }}
              </button>
            </details>
          </footer>
        </article>
      </div>
      <footer
        v-if="total > 20"
        :class="surveyClasses('sv-pagination')"
      >
        <button
          type="button"
          :class="surveyClasses('sv-button')"
          :disabled="busy || page === 1"
          @click="navigate(-1)"
        >
          {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.ANTERIOR_E4CE7C') }}
        </button>
        <span>
          {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PAGINA_8F63F4') }}
          {{ page }} {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.DE_959A45') }}
          {{ Math.ceil(total / 20) }}
        </span>
        <button
          type="button"
          :class="surveyClasses('sv-button')"
          :disabled="busy || page * 20 >= total"
          @click="navigate(1)"
        >
          {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PROXIMA_2FE966') }}
        </button>
      </footer>
    </template>
    <SurveyModelWizard
      v-if="editorOpen && options"
      :key="`${identity}:${editing?.id || 'new'}`"
      :account-id="accountId"
      :unit="unit"
      :options="options"
      :record="editing"
      :api="api"
      @close="closeEditor"
      @saved="changed"
      @published="changed"
    />
    <Teleport to="body">
      <div
        v-if="pendingAction"
        :class="surveyClasses('sv-overlay sv-small-overlay')"
      >
        <section
          :class="surveyClasses('sv-small-dialog')"
          role="dialog"
          aria-modal="true"
          aria-labelledby="sv-action-title"
        >
          <h3 id="sv-action-title">
            {{
              {
                duplicate: 'Duplicar modelo',
                deactivate: 'Desativar pesquisa',
                dispatch: 'Avaliar envio manual',
              }[pendingAction.type]
            }}
          </h3>
          <p v-if="pendingAction.type === 'duplicate'">
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.UMA_COPIA_INATIVA_SERA_SALVA_15A261'
              )
            }}
          </p>
          <p v-else-if="pendingAction.type === 'deactivate'">
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.A_REGRA_DEIXARA_DE_AUTORIZAR_FAD948'
              )
            }}
          </p>
          <template v-else>
            <p>
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ESTA_ACAO_PODE_ENFILEIRAR_UMA_DE9A8C'
                )
              }}
            </p>
            <label>
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NUMERO_INTERNO_DO_CHAMADO_AUTORIZADO_8EB173'
                )
              }}
              <input
                v-model="ticketId"
                inputmode="numeric"
                pattern="[1-9][0-9]*"
              />
            </label>
          </template>
          <p
            v-if="error"
            :class="surveyClasses('sv-alert sv-alert-error')"
          >
            {{ error }}
          </p>
          <footer>
            <button
              type="button"
              :class="surveyClasses('sv-button')"
              :disabled="busy"
              @click="pendingAction = null"
            >
              {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.CANCELAR_BB9DBB') }}
            </button>
            <button
              type="button"
              :class="surveyClasses('sv-button sv-primary')"
              :disabled="
                busy ||
                (pendingAction.type === 'dispatch' &&
                  !/^[1-9]\d*$/.test(ticketId))
              "
              @click="execute"
            >
              {{ busy ? 'Confirmando...' : 'Confirmar' }}
            </button>
          </footer>
        </section>
      </div>
      <div
        v-if="history"
        :class="surveyClasses('sv-overlay sv-small-overlay')"
      >
        <section
          :class="surveyClasses('sv-small-dialog')"
          role="dialog"
          aria-modal="true"
          :aria-label="
            $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.VERSOES_PUBLICADAS_53FBEE')
          "
        >
          <h3>
            {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.VERSOES_DE_7E1156') }}
            {{ history.name }}
          </h3>
          <ul>
            <li
              v-for="row in history.rows"
              :key="row.id"
            >
              {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.VERSAO_15116B') }}
              {{ row.version }}
              {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_BDA050') }}
              {{ date(row.created_at) }}
            </li>
          </ul>
          <p v-if="!history.rows.length">
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.NENHUMA_VERSAO_PUBLICADA_1825E0'
              )
            }}
          </p>
          <button
            type="button"
            :class="surveyClasses('sv-button')"
            @click="history = null"
          >
            {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.FECHAR_0F2BD8') }}
          </button>
        </section>
      </div>
    </Teleport>
  </section>
</template>
