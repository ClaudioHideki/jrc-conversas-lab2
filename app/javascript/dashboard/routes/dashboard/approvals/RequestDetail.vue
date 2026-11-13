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
import Icon from 'next/icon/Icon.vue';
import ApprovalStatus from './ApprovalStatus.vue';
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
const { t, locale } = useI18n();
const displayDate = value =>
  value
    ? new Intl.DateTimeFormat(locale.value.replaceAll('_', '-'), {
        dateStyle: 'short',
        timeStyle: 'short',
      }).format(new Date(value))
    : '—';
const decisionColor = decision =>
  decision === 'approved' ? 'teal' : decision === 'rejected' ? 'ruby' : 'amber';
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
  <section class="min-w-0 space-y-5">
    <header
      class="flex flex-wrap items-start justify-between gap-3 border-b border-n-weak pb-4"
    >
      <div class="flex min-w-0 gap-3">
        <span
          class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-n-blue-3 text-n-blue-11"
          ><Icon
            icon="i-lucide-file-check-2"
            class="size-6"
        /></span>
        <div class="min-w-0">
          <h2 class="break-words text-lg font-bold">
            {{ request.policy_name || t('JRC_APPROVALS.request') }}
          </h2>
          <p class="mt-1 break-words text-xs text-n-slate-11">
            {{ t('JRC_APPROVALS.request') }} #{{ request.id }} ·
            {{ scopeLabel(context, request) || t('JRC_APPROVALS.groupScope') }}
          </p>
        </div>
      </div>
      <ApprovalStatus :state="request.state" />
    </header>
    <dl class="grid min-w-0 gap-4 sm:grid-cols-2">
      <div class="min-w-0">
        <dt class="text-xs font-medium text-n-slate-11">
          {{ t('JRC_APPROVALS.requester_name') }}
        </dt>
        <dd class="mt-1 break-words text-sm font-semibold">
          {{ request.requester_name || '—' }}
        </dd>
      </div>
      <div class="min-w-0">
        <dt class="text-xs font-medium text-n-slate-11">
          {{ t('JRC_APPROVALS.scope') }}
        </dt>
        <dd class="mt-1 break-words text-sm">
          {{ scopeLabel(context, request) || t('JRC_APPROVALS.groupScope') }}
        </dd>
      </div>
      <div class="min-w-0">
        <dt class="text-xs font-medium text-n-slate-11">
          {{ t('JRC_APPROVALS.workspace.requestedAt') }}
        </dt>
        <dd class="mt-1 text-sm">{{ displayDate(request.created_at) }}</dd>
      </div>
      <div class="min-w-0">
        <dt class="text-xs font-medium text-n-slate-11">
          {{ t('JRC_APPROVALS.expires_at') }}
        </dt>
        <dd class="mt-1 text-sm">{{ displayDate(request.expires_at) }}</dd>
      </div>
    </dl>
    <p
      class="rounded-xl border border-n-blue-5 bg-n-blue-2 p-3 text-sm text-n-slate-11"
    >
      {{ t('JRC_APPROVALS.workspace.sourceHelp') }}
    </p>
    <details class="rounded-xl border border-n-weak bg-n-background p-3">
      <summary class="cursor-pointer text-xs font-medium text-n-slate-11">
        {{ t('JRC_APPROVALS.workspace.technicalDetails') }}
      </summary>
      <dl class="mt-3 grid gap-3 text-xs sm:grid-cols-2">
        <div
          v-for="field in [
            'resource_type',
            'resource_id',
            'policy_version',
            'issuer_company_id',
            'business_unit_id',
            'cycle',
          ]"
          :key="field"
        >
          <dt class="text-n-slate-11">{{ t('JRC_APPROVALS.' + field) }}</dt>
          <dd class="break-words">{{ request[field] ?? '—' }}</dd>
        </div>
      </dl>
      <p
        v-for="step in request.stages || []"
        :key="step.code"
        class="mt-3 break-words rounded-lg bg-n-alpha-2 p-2 text-xs"
      >
        {{ step.code }} · {{ step.approved_count }}/{{ step.quorum }}
      </p>
    </details>
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
        v-if="choices.length"
        class="text-xs text-n-slate-11"
      >
        {{ t('JRC_APPROVALS.workspace.decisionHelp') }}
      </p>
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
            :color="decisionColor(choice.decision)"
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
