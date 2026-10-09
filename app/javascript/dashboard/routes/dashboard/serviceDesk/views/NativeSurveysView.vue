<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import RelationshipAPI from 'dashboard/api/jrcRelationship';
import { useI18n } from 'vue-i18n';
import ModulePage from '../../jrcRelationship/ModulePage.vue';
import ScopeBar from '../components/ScopeBar.vue';
import State from '../components/ServiceDeskState.vue';
import { useServiceDesk } from '../composables/useServiceDesk';
import { canonicalId } from '../helpers/access';
const { t } = useI18n();
const session = useServiceDesk();
const router = useRouter();
const mayAdminister = ref(false);
let adminRevision = 0;
let adminController;
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
watch(
  [identity, allowed, () => session.state.context, () => session.state.status],
  async () => {
    adminRevision += 1;
    const revision = adminRevision;
    adminController?.abort();
    mayAdminister.value = false;
    if (!selected.value) return;
    const context = session.state.context;
    adminController = new AbortController();
    try {
      const response = await RelationshipAPI.metadata(context.account_id, {
        signal: adminController.signal,
      });
      if (
        revision !== adminRevision ||
        context !== session.state.context ||
        !selected.value
      )
        return;
      mayAdminister.value = response.data?.can_administer_surveys === true;
    } catch {
      if (revision === adminRevision) mayAdminister.value = false;
    }
  },
  { immediate: true, flush: 'sync' }
);
onBeforeUnmount(() => {
  adminRevision += 1;
  adminController?.abort();
});
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
    <Button
      v-if="selected && mayAdminister"
      variant="outline"
      :label="t('JRC_SERVICE_DESK.EXPERIENCE.manage_surveys')"
      @click="
        router.push({
          name: 'jrc_relationship_survey_admin',
          params: { accountId: session.state.context.account_id },
        })
      "
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
