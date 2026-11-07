<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, message, date } from './definitions';
import ReviewedCadencePanel from './ReviewedCadencePanel.vue';
import DistributionComparison from './DistributionComparison.vue';
import DistributionCapacitySummary from './DistributionCapacitySummary.vue';
import ResponsibilityComparison from './ResponsibilityComparison.vue';
import { intent } from 'dashboard/routes/dashboard/approvals/model';
import { validMembershipReview } from './portfolioMembershipReviewReceipt';
import ReviewedOperationInventory from './ReviewedOperationInventory.vue';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  actorId: { type: [String, Number], default: null },
  authorizationKey: { type: String, default: '' },
  proposal: { type: Object, default: null },
  portfolioGroupId: { type: Number, default: null },
  canExecute: { type: Boolean, default: true },
  showInventory: Boolean,
  formatting: { type: Object, default: () => ({}) },
  owners: { type: Array, default: () => [] },
});
const emit = defineEmits([
  'updated',
  'reviewed',
  'previewFailed',
  'accessDenied',
]);
const { t } = useI18n();
const review = ref(null);
const error = ref('');
const busy = ref(false);
const reading = ref(false);
const uncertain = ref(false);
const executionConfirmed = ref(false);
const savedView = ref(false);
const requestedSavedId = ref(null);
const canExecuteReview = computed(
  () =>
    props.canExecute &&
    !['scope_denied', 'controlled_review_required'].includes(
      review.value?.membership_capacity?.state
    )
);
const approvalIntent = intent();
const responsibilitiesBlocked = computed(() =>
  (review.value?.responsibilities || []).some(
    row => !['ready', 'executed'].includes(row.state)
  )
);
const hasPendingApproval = computed(() =>
  (review.value?.approval?.requests || []).some(
    request =>
      ['pending', 'escalated'].includes(request.state) &&
      (review.value.approval.policy_version_ids || []).includes(
        request.policy_version_id
      )
  )
);
let epoch = 0;
let controller = new AbortController();
let timer;
let preparedAuthority = null;
const authorityKey = () =>
  JSON.stringify([
    props.accountId,
    props.actorId,
    props.authorizationKey,
    props.portfolioGroupId,
  ]);
const storageKey = () =>
  `relationship-reviewed-batch:${props.accountId}:${props.actorId ?? 'operator'}${props.portfolioGroupId ? `:portfolio:${props.portfolioGroupId}` : ''}`;
const stateLabel = state => t(`RELATIONSHIP.REVIEWED_BATCH.STATES.${state}`);
const membershipStateLabels = computed(() => ({
  linked: t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.linked'),
  already_linked: t(
    'RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.already_linked'
  ),
  unlinked: t('RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.unlinked'),
  already_unlinked: t(
    'RELATIONSHIP.NAMED_PORTFOLIOS.MEMBERSHIP.STATES.already_unlinked'
  ),
}));
const failureLabels = computed(() => ({
  BATCH_REVIEW_STALE: t('RELATIONSHIP.REVIEWED_BATCH.FAILURES.STALE'),
  BATCH_REVIEW_EXPIRED: t('RELATIONSHIP.REVIEWED_BATCH.FAILURES.EXPIRED'),
  BATCH_RECEIPT_INVALID: t('RELATIONSHIP.REVIEWED_BATCH.FAILURES.RECEIPT'),
  BATCH_CAPACITY_EXCEEDED: t('RELATIONSHIP.REVIEWED_BATCH.FAILURES.CAPACITY'),
  BATCH_CAPACITY_UNCONFIGURED: t(
    'RELATIONSHIP.REVIEWED_BATCH.FAILURES.UNCONFIGURED'
  ),
  BATCH_CAPACITY_UNAVAILABLE: t(
    'RELATIONSHIP.REVIEWED_BATCH.FAILURES.UNAVAILABLE'
  ),
  BATCH_NATIVE_VALIDATION_FAILED: t(
    'RELATIONSHIP.REVIEWED_BATCH.FAILURES.VALIDATION'
  ),
}));
const membershipCapacityLabels = computed(() => ({
  projected: t('RELATIONSHIP.MEMBERSHIP_CAPACITY.PROJECTED'),
  not_configured: t('RELATIONSHIP.MEMBERSHIP_CAPACITY.NOT_CONFIGURED'),
  scope_denied: t('RELATIONSHIP.MEMBERSHIP_CAPACITY.SCOPE_DENIED'),
  controlled_review_required: t(
    'RELATIONSHIP.MEMBERSHIP_CAPACITY.CONTROLLED_REVIEW'
  ),
}));
const reset = () => {
  epoch += 1;
  controller.abort();
  controller = new AbortController();
  clearInterval(timer);
  review.value = null;
  error.value = '';
  busy.value = false;
  reading.value = false;
  uncertain.value = false;
  executionConfirmed.value = false;
  preparedAuthority = null;
  savedView.value = false;
  requestedSavedId.value = null;
};
const remember = value => {
  if (
    (props.portfolioGroupId !== null ||
      value.inputs?.operation === 'portfolio_membership') &&
    !validMembershipReview(
      value,
      props.portfolioGroupId,
      savedView.value ? null : props.proposal
    )
  ) {
    review.value = null;
    uncertain.value = true;
    executionConfirmed.value = false;
    clearInterval(timer);
    throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.UNCONFIRMED'));
  }
  if (review.value?.id === value.id && review.value.revision > value.revision)
    return;
  const previous = review.value;
  if (
    JSON.stringify([previous?.id, previous?.digest, previous?.approval]) !==
    JSON.stringify([value.id, value.digest, value.approval])
  )
    executionConfirmed.value = false;
  review.value = value;
  emit('reviewed', value);
  try {
    sessionStorage.setItem(storageKey(), String(value.id));
  } catch {
    /* Recovery is also available through the saved server operation. */
  }
  clearInterval(timer);
  if (value.state === 'running')
    timer = setInterval(() => {
      // Timer runs after setup has initialized both mutually recursive handlers.
      // eslint-disable-next-line no-use-before-define
      if (!busy.value && !reading.value) refresh();
    }, 2000);
  if (
    previous?.id === value.id &&
    previous.revision < value.revision &&
    ['completed', 'canceled', 'attention'].includes(value.state)
  )
    emit('updated');
};
const clearDenied = failure => {
  const status = failure.response?.status;
  if (![401, 403, 404].includes(status)) return;
  review.value = null;
  uncertain.value = true;
  executionConfirmed.value = false;
  preparedAuthority = null;
  clearInterval(timer);
  emit('accessDenied', status);
};
async function prepare(proposal) {
  if (!proposal) {
    if (!review.value || review.value.state === 'previewed') reset();
    return;
  }
  reset();
  preparedAuthority = authorityKey();
  const version = epoch;
  const accountId = props.accountId;
  busy.value = true;
  try {
    const { data } = await API.previewPortfolioBatch(accountId, proposal, {
      signal: controller.signal,
    });
    if (version === epoch) remember(data);
  } catch (failure) {
    if (version === epoch) {
      error.value = message(failure) || t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
      clearDenied(failure);
      emit('previewFailed', failure.response?.status ?? null);
    }
  } finally {
    if (version === epoch) busy.value = false;
  }
}
async function readSaved(id) {
  if (!Number.isSafeInteger(id) || id < 1) return;
  const version = epoch;
  const accountId = props.accountId;
  reading.value = true;
  try {
    const { data } = await API.portfolioBatchReview(accountId, id, {
      signal: controller.signal,
    });
    if (version === epoch) {
      if (data.id !== id)
        throw new Error(t('RELATIONSHIP.REVIEWED_INVENTORY.UNCONFIRMED'));
      remember(data);
      uncertain.value = false;
      error.value = '';
    }
  } catch (failure) {
    if (version === epoch) {
      error.value = message(failure) || t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
      clearDenied(failure);
    }
  } finally {
    if (version === epoch) reading.value = false;
  }
}
async function openSaved(id) {
  if (busy.value || reading.value) return;
  reset();
  savedView.value = true;
  requestedSavedId.value = id;
  emit('reviewed', null);
  await readSaved(id);
}
async function refresh() {
  if (busy.value || reading.value) return;
  if (
    props.portfolioGroupId &&
    !review.value &&
    props.proposal &&
    preparedAuthority === authorityKey()
  ) {
    await prepare(props.proposal);
    return;
  }
  let id = review.value?.id || requestedSavedId.value;
  try {
    id ||= Number(sessionStorage.getItem(storageKey()));
  } catch {
    /* No cached operation. */
  }
  if (!Number.isSafeInteger(id) || id < 1 || reading.value) return;
  await readSaved(id);
}
async function mutate(action) {
  if (busy.value || !review.value) return;
  if (
    ['approve', 'advance', 'requestApproval'].includes(action) &&
    !canExecuteReview.value
  )
    return;
  if (
    action === 'approve' &&
    review.value.approval?.required &&
    (review.value.approval.state !== 'approved' || !executionConfirmed.value)
  )
    return;
  epoch += 1;
  const version = epoch;
  const accountId = props.accountId;
  const current = review.value;
  controller.abort();
  controller = new AbortController();
  reading.value = false;
  busy.value = true;
  try {
    const options = { signal: controller.signal };
    let response;
    if (action === 'requestApproval')
      response = await API.requestPortfolioBatchApproval(
        accountId,
        current.id,
        approvalIntent(
          { digest: current.digest },
          JSON.stringify([
            accountId,
            current.id,
            current.approval?.policy_version_ids,
            current.approval?.requests,
          ])
        ),
        options
      );
    else if (action === 'approve')
      response = await API.approvePortfolioBatch(
        accountId,
        current.id,
        current.digest,
        options
      );
    else if (action === 'cancel')
      response = await API.cancelPortfolioBatch(accountId, current.id, options);
    else
      response = await API.advancePortfolioBatch(
        accountId,
        current.id,
        options
      );
    const { data } = response;
    if (version === epoch) {
      remember(data);
      uncertain.value = false;
      error.value = '';
    }
  } catch (failure) {
    if (version === epoch) {
      error.value = message(failure) || t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
      uncertain.value = true;
      clearDenied(failure);
    }
  } finally {
    if (version === epoch) busy.value = false;
  }
}

watch(() => props.proposal, prepare, { immediate: true, deep: true });
watch(
  [
    () => props.accountId,
    () => props.actorId,
    () => props.authorizationKey,
    () => props.portfolioGroupId,
  ],
  reset
);
onMounted(() => {
  if (!props.proposal) refresh();
});
onBeforeUnmount(reset);
</script>

<template>
  <section
    class="mt-3 rounded-xl border border-n-weak p-4"
    aria-live="polite"
  >
    <h3 class="font-semibold">{{ t('RELATIONSHIP.REVIEWED_BATCH.TITLE') }}</h3>
    <ReviewedOperationInventory
      v-if="showInventory && actorId"
      :account-id="accountId"
      :actor-id="actorId"
      :authorization-key="authorizationKey"
      :portfolio-group-id="portfolioGroupId"
      :formatting="formatting"
      :disabled="busy || reading"
      @open="openSaved"
      @updated="
        refresh();
        emit('updated');
      "
    />
    <p class="mt-2 text-sm">
      {{ t('RELATIONSHIP.REVIEWED_BATCH.DESCRIPTION') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="mt-2 text-sm"
    >
      {{ error }}
    </p>
    <p
      v-if="busy"
      class="mt-2 text-sm"
    >
      {{ t('RELATIONSHIP.REVIEWED_BATCH.WORKING') }}
    </p>
    <template v-if="review">
      <p class="mt-2 font-medium">{{ stateLabel(review.state) }}</p>
      <p
        v-if="review.source_access_limited"
        data-test="review-limited-receipt"
        class="my-2 rounded-lg border border-n-blue-6 bg-n-blue-2 p-3 text-sm text-n-slate-12"
      >
        {{ t('RELATIONSHIP.REVIEWED_BATCH.LIMITED_RECEIPT') }}
      </p>
      <p class="text-sm">
        {{
          t('RELATIONSHIP.REVIEWED_BATCH.IDENTITY', {
            id: review.id,
            revision: review.revision,
          })
        }}
      </p>
      <p class="text-sm">
        {{
          t(`RELATIONSHIP.REVIEWED_BATCH.OPERATIONS.${review.inputs.operation}`)
        }}
      </p>
      <p
        v-if="review.summary && review.inputs.operation === 'assign'"
        class="text-sm"
      >
        {{
          t('RELATIONSHIP.REVIEWED_BATCH.OWNER', {
            name: review.summary.owner_name || t('RELATIONSHIP.UNASSIGNED'),
          })
        }}
      </p>
      <p
        v-if="review.summary?.book_name"
        class="text-sm"
      >
        {{
          t('RELATIONSHIP.REVIEWED_BATCH.BOOK', {
            name: review.summary.book_name,
            version: review.summary.book_version,
          })
        }}
      </p>
      <p
        v-if="review.inputs.operation === 'portfolio_membership'"
        class="min-w-0 break-words text-sm"
      >
        {{ review.summary.portfolio_group_name }}
      </p>
      <p
        v-if="review.inputs.title"
        class="text-sm"
      >
        {{ review.inputs.title }} · {{ review.inputs.due_at }}
      </p>
      <div v-if="review.inputs.operation === 'cadence'">
        <p>
          {{
            t('RELATIONSHIP.REVIEWED_BATCH.CADENCE_TARGET', {
              name: review.summary.contact_name,
              number: review.summary.conversation_number,
            })
          }}
        </p>
        <ul>
          <li
            v-for="(step, index) in review.summary.schedule"
            :key="index"
          >
            <p>{{ step.title }}</p>
            <p>{{ step.due_at }}</p>
          </li>
        </ul>
      </div>
      <DistributionComparison
        v-if="review.distribution?.length"
        :rows="review.distribution"
      />
      <DistributionCapacitySummary :rows="review.capacity || []" />
      <section
        v-if="
          review.inputs.operation === 'portfolio_membership' &&
          review.membership_capacity
        "
        class="my-3 min-w-0 space-y-2 rounded-xl border border-n-violet-6 bg-n-solid-2 p-3"
      >
        <h3 class="font-semibold">
          {{ t('RELATIONSHIP.MEMBERSHIP_CAPACITY.TITLE') }}
        </h3>
        <p class="break-words text-sm">
          {{
            t('RELATIONSHIP.MEMBERSHIP_CAPACITY.NOTICE', {
              date: date(review.membership_capacity.captured_at, formatting),
            })
          }}
        </p>
        <p class="text-sm">
          {{ membershipCapacityLabels[review.membership_capacity.state] }}
        </p>
        <DistributionCapacitySummary
          :rows="review.membership_capacity.rows"
          show-owner
          :owners="owners"
        />
      </section>
      <ResponsibilityComparison
        :rows="review.responsibilities || []"
        :owner-name="review.summary?.owner_name || ''"
      />
      <section
        v-if="review.approval?.required"
        class="my-3 space-y-3 rounded-xl border border-n-violet-6 bg-n-violet-2 p-3"
      >
        <p class="text-sm">
          {{ t('RELATIONSHIP.DISTRIBUTION.CENTRAL_NOTICE') }}
        </p>
        <p class="font-semibold">
          {{ t(`RELATIONSHIP.DISTRIBUTION.STATES.${review.approval.state}`) }}
        </p>
        <RouterLink
          v-for="request in review.approval.requests"
          :key="request.id"
          :to="{
            name: 'jrc_approvals',
            params: { accountId, screen: 'inbox', id: request.id },
          }"
          class="block text-sm text-n-blue-11 underline"
        >
          #{{ request.id }} · {{ request.state }}
        </RouterLink>
        <button
          v-if="
            review.state === 'previewed' &&
            review.approval.state === 'required' &&
            !hasPendingApproval
          "
          type="button"
          data-test="review-request-approval"
          :class="buttonClass"
          :disabled="
            busy ||
            !canExecuteReview ||
            uncertain ||
            responsibilitiesBlocked ||
            review.capacity?.some(row => row.blocker)
          "
          @click="mutate('requestApproval')"
        >
          {{ t('RELATIONSHIP.DISTRIBUTION.REQUEST_APPROVAL') }}
        </button>
        <label
          v-if="
            review.state === 'previewed' && review.approval.state === 'approved'
          "
          class="flex items-start gap-2 text-sm"
        >
          <input
            v-model="executionConfirmed"
            type="checkbox"
            data-test="review-execution-confirmation"
          />
          {{ t('RELATIONSHIP.DISTRIBUTION.CONFIRM_EXECUTION') }}
        </label>
      </section>
      <ul class="my-3 space-y-2">
        <li
          v-for="item in review.items"
          :key="item.assignment_id"
          class="text-sm"
        >
          {{ item.label || t('RELATIONSHIP.REVIEWED_BATCH.RECEIPT_ITEM') }} ·
          {{ stateLabel(item.state) }}
          <span
            v-if="item.receipt?.membership_state"
            class="block"
          >
            {{ membershipStateLabels[item.receipt.membership_state] }}
          </span>
          <span
            v-if="item.error_code"
            class="block"
          >
            {{
              Object.hasOwn(failureLabels, item.error_code)
                ? failureLabels[item.error_code]
                : t('RELATIONSHIP.REVIEWED_BATCH.ITEM_FAILED')
            }}
          </span>
          <ReviewedCadencePanel
            v-if="item.receipt?.cadence_id"
            :account-id="accountId"
            :cadence-id="item.receipt.cadence_id"
          />
        </li>
      </ul>
      <div class="flex flex-wrap gap-2">
        <button
          v-if="review.state === 'previewed'"
          type="button"
          data-test="review-approve"
          :class="buttonClass"
          :disabled="
            busy ||
            !canExecuteReview ||
            uncertain ||
            responsibilitiesBlocked ||
            review.capacity?.some(row => row.blocker) ||
            (review.approval?.required &&
              (review.approval.state !== 'approved' || !executionConfirmed))
          "
          @click="mutate('approve')"
        >
          {{
            t(
              review.approval?.required
                ? 'RELATIONSHIP.DISTRIBUTION.EXECUTE'
                : 'RELATIONSHIP.REVIEWED_BATCH.APPROVE'
            )
          }}
        </button>
        <button
          v-if="review.state === 'running'"
          type="button"
          data-test="review-advance"
          :class="buttonClass"
          :disabled="busy || uncertain || !canExecuteReview"
          @click="mutate('advance')"
        >
          {{ t('RELATIONSHIP.REVIEWED_BATCH.ADVANCE') }}
        </button>
        <button
          v-if="['previewed', 'running'].includes(review.state)"
          type="button"
          data-test="review-cancel"
          :class="buttonClass"
          :disabled="busy"
          @click="mutate('cancel')"
        >
          {{ t('RELATIONSHIP.REVIEWED_BATCH.CANCEL') }}
        </button>
      </div>
    </template>
    <button
      type="button"
      data-test="review-refresh"
      class="mt-3"
      :class="[buttonClass]"
      :disabled="busy || reading"
      @click="refresh"
    >
      {{ t('RELATIONSHIP.REVIEWED_BATCH.REFRESH') }}
    </button>
  </section>
</template>
