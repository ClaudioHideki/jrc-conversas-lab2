<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ModulePage from '../../jrcRelationship/ModulePage.vue';
import ScopeBar from '../components/ScopeBar.vue';
import State from '../components/ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
const { t } = useI18n();
const session = useServiceDesk();
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
    <ModulePage
      v-if="selected"
      :key="identity"
      screen="surveys"
      :fixed-survey-scope="{
        source_type: 'JrcServiceDesk::Ticket',
        unit_id: selected.id,
      }"
      data-testid="native-surveys"
    />
    <State
      v-else
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
