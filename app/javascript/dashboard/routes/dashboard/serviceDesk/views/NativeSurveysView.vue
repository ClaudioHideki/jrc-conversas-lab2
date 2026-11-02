<script setup>
import { surveyClasses } from '../surveys/surveyClasses';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SurveyModelsManager from '../surveys/SurveyModelsManager.vue';
import ModulePage from '../../jrcRelationship/ModulePage.vue';
import ScopeBar from '../components/ScopeBar.vue';
import State from '../components/ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
const { t } = useI18n();
const session = useServiceDesk();
const tab = ref('results');
const unitId = ref('');
const operatorId = ref('');
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.surveys?.index === true
);
const selected = computed(
  () =>
    allowed.value &&
    session.state.context.units.find(
      unit => unit.id === canonicalId(unitId.value)
    )
);
const identity = computed(
  () =>
    `${session.state.context?.account_id}:${session.state.context?.user_id}:${selected.value?.id}`
);
watch(
  [() => session.state.context, () => session.state.status],
  () => {
    tab.value = 'results';
    unitId.value = '';
    operatorId.value = '';
  },
  { flush: 'sync' }
);
</script>

<template>
  <section class="grid gap-4">
    <h2 class="sd-page-title">{{ t('JRC_SERVICE_DESK.SCREENS.surveys') }}</h2>
    <p class="text-sm text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.SURVEYS.native_scope') }}
    </p>
    <ScopeBar
      v-if="allowed"
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      data-testid="native-survey-scope"
    />
    <p v-if="selected" class="rounded-lg border border-n-weak p-3 text-sm">
      {{
        t('JRC_SERVICE_DESK.EXPERIENCE.survey_scope_help', {
          unit: selected.name,
        })
      }}
    </p>
    <nav
      v-if="selected"
      :class="surveyClasses('sv-native-tabs')"
      :aria-label="
        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PESQUISAS_DE_SATISFACAO_ABE38A')
      "
    >
      <button
        type="button"
        :class="surveyClasses('sv-button')"
        :aria-selected="tab === 'results'"
        @click="tab = 'results'"
      >
        {{
          $t(
            'RELATIONSHIP.SURVEY_MODELS_V3.COPY.RESPOSTAS_E_INDICADORES_B03807'
          )
        }}
      </button>
      <button
        type="button"
        :class="surveyClasses('sv-button')"
        :aria-selected="tab === 'models'"
        @click="tab = 'models'"
      >
        {{
          $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.MODELOS_DE_PESQUISA_7678A4')
        }}
      </button>
    </nav>
    <SurveyModelsManager
      v-if="selected && tab === 'models'"
      :key="identity"
      :account-id="session.state.context.account_id"
      :unit="selected"
    />
    <ModulePage
      v-if="selected && tab === 'results'"
      :key="identity"
      screen="surveys"
      :fixed-survey-scope="{
        source_type: 'JrcServiceDesk::Ticket',
        unit_id: selected.id,
      }"
      data-testid="native-surveys"
    />
    <State
      v-if="!selected"
      :status="
        allowed
          ? 'idle'
          : session.state.status === 'ready'
            ? 'denied'
            : session.state.status
      "
      :description="allowed ? t('JRC_SERVICE_DESK.SCOPE.unselected') : ''"
      compact
    />
  </section>
</template>
