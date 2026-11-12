<script setup>
import { surveyClasses } from '../surveys/surveyClasses';
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SatisfactionDashboard from '../components/SatisfactionDashboard.vue';
import SurveyModelsManager from '../surveys/SurveyModelsManager.vue';
import ModulePage from '../../jrcRelationship/ModulePage.vue';
import ScopeBar from '../components/ScopeBar.vue';
import State from '../components/ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
const { t } = useI18n();
const session = useServiceDesk();
const tab = ref('overview');
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
    tab.value = 'overview';
    unitId.value = '';
    operatorId.value = '';
  },
  { flush: 'sync' }
);
</script>

<template>
  <section class="grid gap-4">
    <header
      class="rounded-2xl bg-gradient-to-r from-[#031a3a] via-[#073f82] to-blue-700 p-5 text-white shadow-md"
    >
      <h2 class="m-0 flex items-center gap-3 text-2xl font-bold !text-white">
        <span aria-hidden="true" class="i-lucide-user-round-check size-8" />{{
          t('JRC_SERVICE_DESK.SCREENS.surveys')
        }}
      </h2>
      <p class="mb-0 mt-2 text-sm text-blue-100">
        {{ t('JRC_SERVICE_DESK.SATISFACTION.subtitle') }}
      </p>
    </header>
    <ScopeBar
      v-if="allowed"
      v-model:unit-id="unitId"
      v-model:operator-id="operatorId"
      required
      class="rounded-xl border border-blue-200 bg-n-solid-1 p-3 [&>p]:hidden"
      data-testid="native-survey-scope"
    />
    <nav
      v-if="selected"
      :class="surveyClasses('sv-native-tabs')"
      :aria-label="
        $t('RELATIONSHIP.SURVEY_MODELS_V3.COPY.PESQUISAS_DE_SATISFACAO_ABE38A')
      "
    >
      <button
        type="button"
        :class="[
          surveyClasses('sv-button'),
          tab === 'overview' ? '!bg-blue-600 !text-white' : '',
        ]"
        :aria-selected="tab === 'overview'"
        @click="tab = 'overview'"
      >
        {{ t('JRC_SERVICE_DESK.SATISFACTION.overview') }}
      </button>
      <button
        type="button"
        :class="surveyClasses('sv-button')"
        :aria-selected="tab === 'results'"
        @click="tab = 'results'"
      >
        {{ t('JRC_SERVICE_DESK.SATISFACTION.responses_tab') }}
      </button>
      <button
        type="button"
        :class="surveyClasses('sv-button')"
        :aria-selected="tab === 'models'"
        @click="tab = 'models'"
      >
        {{ t('JRC_SERVICE_DESK.SATISFACTION.models_rules') }}
      </button>
    </nav>
    <SatisfactionDashboard
      v-if="selected && tab === 'overview'"
      :key="identity"
      :unit-id="selected.id"
      @responses="tab = 'results'"
    />
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
