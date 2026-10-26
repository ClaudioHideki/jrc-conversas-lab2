<script setup>
import { surveyClasses } from './surveyClasses';
import { reactive, toRefs, computed } from 'vue';
import { CHANNELS } from './modelForm';
const props = defineProps({ model: { type: Object, required: true } });
defineOptions({ name: 'SurveyModelPreview' });
const state = reactive(
  (() => {
    return { channel: 'whatsapp', mode: 'form', channels: CHANNELS };
  })()
);
const { channel, mode, channels } = toRefs(state);

const questions = computed(() => {
  return props.model.questions;
});
const message = computed(() => {
  const cfg = props.model.channels[state.channel];
  return (cfg?.whatsapp_template?.content || cfg?.message || '').replace(
    /\{\{survey_(?:link|url)\}\}/g,
    '[link seguro da pesquisa]'
  );
});
function scores(q) {
  return Array.from(
    { length: Math.min(11, Math.max(0, q.max - q.min + 1)) },
    (_, i) => q.min + i
  );
}

defineExpose({ ...toRefs(state), questions, message, scores });
</script>

<template>
  <aside
    :class="surveyClasses('sv-preview')"
    :aria-label="
      $t(
        'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PREVISUALIZACAO_DA_PESQUISA_E0AD5C'
      )
    "
  >
    <div :class="surveyClasses('sv-preview-heading')">
      <span class="i-lucide-panel-right" />
      {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PREVISUALIZACAO_45F182') }}
      <span :class="surveyClasses('sv-preview-live')">
        {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.AO_VIVO_6872FC') }}
      </span>
    </div>
    <div
      :class="surveyClasses('sv-preview-tabs')"
      role="tablist"
      :aria-label="
        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.CANAL_DA_PREVIA_98A8DE')
      "
    >
      <button
        v-for="item in channels"
        :key="item.key"
        type="button"
        :class="
          surveyClasses([
            'sv-preview-tab',
            item.tone,
            { selected: channel === item.key },
          ])
        "
        role="tab"
        :aria-selected="channel === item.key"
        @click="channel = item.key"
      >
        <span :class="item.icon" />
        {{ item.label === 'Portal do cliente' ? 'Portal' : item.label }}
      </button>
    </div>
    <div
      v-if="channel !== 'public_link'"
      :class="surveyClasses('sv-preview-mode')"
    >
      <button
        type="button"
        :class="{ selected: mode === 'message' }"
        @click="mode = 'message'"
      >
        {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.MENSAGEM_322085') }}
      </button>
      <button
        type="button"
        :class="{ selected: mode === 'form' }"
        @click="mode = 'form'"
      >
        {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.FORMULARIO_DO_LINK_B6FD4E') }}
      </button>
    </div>
    <div
      :class="
        surveyClasses([
          'sv-phone',
          {
            'sv-phone-email': channel === 'email',
            'sv-phone-portal': channel === 'public_link',
          },
        ])
      "
    >
      <header :class="surveyClasses('sv-phone-header')">
        <span :class="surveyClasses('sv-jrc-avatar')">
          {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.JRC_B7CB76') }}
        </span>
        <div>
          <strong>
            {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.JRC_CONVERSAS_E61F5B') }}
          </strong>
          <small>
            {{
              channel === 'public_link'
                ? 'Portal do cliente'
                : 'Pesquisa de satisfação'
            }}
          </small>
        </div>
        <span class="i-lucide-shield-check" />
      </header>
      <div :class="surveyClasses('sv-preview-paper')">
        <template v-if="mode === 'message' && channel !== 'public_link'">
          <p :class="surveyClasses('sv-message-preview')">
            {{ message || 'Configure a mensagem deste canal.' }}
          </p>
          <div :class="surveyClasses('sv-preview-link')">
            {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.ABRIR_PESQUISA_A63727') }}
            <span class="i-lucide-external-link" />
          </div>
        </template>
        <template v-else>
          <span :class="surveyClasses('sv-preview-eyebrow')">
            {{
              $t(
                'RELATIONSHIP.SURVEY_MODELS_V3.COPY.SUA_OPINIAO_IMPORTA_B4F026'
              )
            }}
          </span>
          <h4>{{ model.name || 'Como foi seu atendimento?' }}</h4>
          <p
            v-if="model.description"
            :class="surveyClasses('sv-preview-description')"
          >
            {{ model.description }}
          </p>
          <div
            v-for="(q, index) in questions"
            :key="`${q.key}-${index}`"
            :class="surveyClasses('sv-preview-question')"
          >
            <p>
              <b>
                {{ index + 1
                }}{{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_CDB4EE') }}
              </b>
              {{ q.text || 'Texto da pergunta' }}
              <span
                v-if="q.required"
                :class="surveyClasses('sv-required')"
              >
                {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.SYMBOL_684888') }}
              </span>
            </p>
            <div
              v-if="q.type === 'scale'"
              :class="
                surveyClasses([
                  'sv-score-grid',
                  { stars: q.presentation === 'stars' },
                ])
              "
            >
              <span
                v-for="value in scores(q)"
                :key="value"
              >
                {{ q.presentation === 'stars' ? '★' : value }}
              </span>
              <small v-if="q.max - q.min > 10">
                {{ q.min }}
                {{ $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.A_CA9781') }}
                {{ q.max }}
              </small>
            </div>
            <div
              v-else-if="q.type === 'choice'"
              :class="surveyClasses('sv-preview-options')"
            >
              <span
                v-for="(option, i) in q.options"
                :key="option.value || i"
              >
                <i />
                {{ option.label || `Opção ${i + 1}` }}
              </span>
            </div>
            <div
              v-else
              :class="surveyClasses('sv-preview-text')"
            >
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ESCREVA_SUA_RESPOSTA_D04D96'
                )
              }}
            </div>
            <small v-if="q.condition">
              {{
                $t(
                  'RELATIONSHIP.SURVEY_MODELS_V3.COPY.EXIBIDA_CONFORME_A_RESPOSTA_ANTERIOR_66E761'
                )
              }}
            </small>
          </div>
          <span :class="surveyClasses('sv-preview-submit')">
            {{
              $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.ENVIAR_RESPOSTA_9CB5D6')
            }}
          </span>
        </template>
      </div>
    </div>
    <p :class="surveyClasses('sv-preview-note')">
      <span class="i-lucide-info" />
      {{
        $t(
          'RELATIONSHIP.SURVEY_MODELS_V3.COPY.PREVIA_SEM_ENVIO_WHATSAPP_E_FEF4E2'
        )
      }}
    </p>
    <div :class="surveyClasses('sv-preview-safe')">
      <span class="i-lucide-lock-keyhole" />
      <div>
        <strong>
          {{
            $t(
              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.ORIGEM_E_VERSAO_PRESERVADAS_18A9B9'
            )
          }}
        </strong>
        <small>
          {{
            $t(
              'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RESPOSTAS_VINCULADAS_AO_CHAMADO_E_F78621'
            )
          }}
        </small>
      </div>
    </div>
  </aside>
</template>
