<script setup>
import { computed, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { decisionChoices, scopeLabel } from './model';
import ApprovalOriginLink from './ApprovalOriginLink.vue';
import ApprovalDecisionDialog from './ApprovalDecisionDialog.vue';
import AuthorityOrigin from './AuthorityOrigin.vue';
import AdjustmentDialog from './AdjustmentDialog.vue';
import FinancialAdjustmentDialog from './FinancialAdjustmentDialog.vue';
import ReviewDirectionsPanel from './ReviewDirectionsPanel.vue';
import ApprovalRequestReport from './ApprovalRequestReport.vue';
import DistributionApprovalOrigin from './DistributionApprovalOrigin.vue';
const props = defineProps({
  request: { type: Object, required: true },
  context: { type: Object, default: null },
  busy: Boolean,
  auditAllowed: Boolean,
  readOnly: Boolean,
  error: { type: String, default: '' },
  errorState: { type: Object, default: null },
});
const emit = defineEmits(['decide', 'adjust', 'audit', 'refresh']);
const { t } = useI18n();
const reason = ref('');
const choices = computed(() => decisionChoices(props.request));
const selectedChoice = ref(null);
const adjusting = ref(false);
const authoritySection = ref(null);
const showAuthority = async () => {
  selectedChoice.value = null;
  await nextTick();
  authoritySection.value?.scrollIntoView({ block: 'start' });
  authoritySection.value?.focus({ preventScroll: true });
};
const choose = choice => {
  if (!props.readOnly && !props.busy && reason.value.trim())
    selectedChoice.value = choice;
};
const label = (choice, index) => {
  const action = t(`JRC_APPROVALS.decisionLabels.${choice.decision}`);
  const step =
    Math.max(
      0,
      (props.request.stages || []).findIndex(
        row => row.code === choice.step_code
      )
    ) + 1;
  let delegation = '';
  if (choice.delegation_id || choice.own_delegation_id) {
    delegation = choice.principal_name
      ? t('JRC_APPROVALS.onBehalfOf', { name: choice.principal_name })
      : t('JRC_APPROVALS.delegatedOption', { number: index + 1 });
  }
  return [action, t('JRC_APPROVALS.stepNumber', { number: step }), delegation]
    .filter(Boolean)
    .join(' · ');
};
watch(
  () =>
    JSON.stringify([
      props.context?.account_id,
      props.context?.member_id,
      props.request.id,
      props.request.lock_version,
      props.request.state,
      props.request.allowed_decisions,
      props.readOnly,
    ]),
  () => {
    selectedChoice.value = null;
    adjusting.value = false;
  }
);
const confirm = payload => {
  if (
    !props.readOnly &&
    !props.busy &&
    selectedChoice.value &&
    props.request.lock_version === payload.expected_version
  )
    emit('decide', payload);
};
</script>

<template>
  <section class="space-y-5">
    <h2 class="text-xl font-semibold">
      {{ t('JRC_APPROVALS.request') }} #{{ request.id }}
    </h2>
    <p class="text-sm">
      {{ scopeLabel(context, request) || t('JRC_APPROVALS.groupScope') }}
    </p>
    <dl
      class="grid gap-3 rounded-xl border border-n-weak bg-n-solid-2 p-4 sm:grid-cols-2"
    >
      <div
        v-for="field in [
          'resource_type',
          'resource_id',
          'requester_name',
          'policy_name',
          'policy_version',
          'issuer_company_id',
          'business_unit_id',
          'state',
          'expires_at',
          'cycle',
        ]"
        :key="field"
      >
        <dt class="text-xs text-n-slate-11">
          {{ t(`JRC_APPROVALS.${field}`) }}
        </dt>
        <dd class="break-words text-sm">{{ request[field] ?? '—' }}</dd>
      </div>
    </dl>
    <div class="space-y-2">
      <h3 class="font-semibold">{{ t('JRC_APPROVALS.steps') }}</h3>
      <p
        v-for="step in request.stages || []"
        :key="step.code"
        class="rounded-lg border border-n-weak p-3 text-sm"
      >
        {{ step.code }} · {{ step.approved_count }}/{{ step.quorum }}
      </p>
    </div>
    <section
      v-if="request.origin?.kind === 'portfolio_distribution'"
      ref="authoritySection"
      tabindex="-1"
    >
      <DistributionApprovalOrigin :request="request" />
    </section>
    <ApprovalOriginLink
      :request="request"
      :account-id="context?.account_id"
      @authority="showAuthority"
    />
    <section
      v-if="request.origin?.kind === 'contract_authority'"
      ref="authoritySection"
      tabindex="-1"
    >
      <AuthorityOrigin
        :key="request.id"
        :request="request"
      />
    </section>
    <section
      v-if="!readOnly"
      class="space-y-3"
    >
      <h3 class="font-semibold">{{ t('JRC_APPROVALS.decision') }}</h3>
      <p
        v-if="!choices.length"
        class="text-sm text-n-slate-11"
      >
        {{ t('JRC_APPROVALS.noDecision') }}
      </p>
      <template v-else>
        <label class="block text-sm"
          ><span>{{ t('JRC_APPROVALS.reason') }}</span
          ><textarea
            v-model="reason"
            required
            class="mt-1 w-full rounded-lg border border-n-weak bg-n-solid-2 p-3"
            rows="3"
          />
        </label>
        <div class="flex flex-wrap gap-2">
          <Button
            v-for="(choice, index) in choices"
            :key="index"
            :label="label(choice, index)"
            :disabled="busy || !reason.trim()"
            @click="choose(choice)"
          />
        </div>
      </template>
    </section>
    <Button
      v-if="!readOnly && request.adjustment && request.state === 'pending'"
      :label="t('JRC_APPROVALS.adjustment.title')"
      :disabled="busy"
      @click="adjusting = true"
    />
    <component
      :is="
        request.adjustment?.financial
          ? FinancialAdjustmentDialog
          : AdjustmentDialog
      "
      v-if="!readOnly && adjusting && request.adjustment"
      :request="request"
      :busy="busy"
      :error="error"
      :error-state="errorState"
      @close="adjusting = false"
      @confirm="emit('adjust', $event)"
    />
    <ReviewDirectionsPanel
      v-if="!readOnly && context && request.review_directions"
      :request="request"
      :context="context"
      :busy="busy"
      @recorded="emit('refresh')"
    />
    <ApprovalDecisionDialog
      v-if="!readOnly && selectedChoice"
      :request="request"
      :choice="selectedChoice"
      :context="context"
      :reason="reason"
      :busy="busy"
      :error="error"
      :error-state="errorState"
      @close="selectedChoice = null"
      @confirm="confirm"
    >
      <template #origin>
        <ApprovalOriginLink
          :request="request"
          :account-id="context?.account_id"
          @authority="showAuthority"
        />
      </template>
    </ApprovalDecisionDialog>
    <section class="space-y-3">
      <h3 class="font-semibold">{{ t('JRC_APPROVALS.decisions') }}</h3>
      <p
        v-if="!request.decisions?.length"
        class="text-sm"
      >
        {{ t('JRC_APPROVALS.empty') }}
      </p>
      <article
        v-for="decision in request.decisions || []"
        :key="decision.id"
        class="rounded-xl border border-n-weak p-3 text-sm"
      >
        <p>
          {{ t(`JRC_APPROVALS.decisionLabels.${decision.decision}`) }} ·
          {{ decision.actor_name }}
        </p>
        <p v-if="decision.delegated_from_name">
          {{
            t('JRC_APPROVALS.onBehalfOf', {
              name: decision.delegated_from_name,
            })
          }}
        </p>
        <p class="my-2 whitespace-pre-wrap">{{ decision.reason }}</p>
        <p class="text-xs text-n-slate-11">
          {{ decision.created_at }} · {{ t('JRC_APPROVALS.cycle') }}
          {{ decision.cycle }}
        </p>
      </article>
    </section>
    <Button
      v-if="auditAllowed && !readOnly"
      :label="t('JRC_APPROVALS.history')"
      variant="faded"
      @click="emit('audit')"
    />
    <ApprovalRequestReport
      v-if="auditAllowed && context"
      :request="request"
      :context="context"
    />
  </section>
</template>
