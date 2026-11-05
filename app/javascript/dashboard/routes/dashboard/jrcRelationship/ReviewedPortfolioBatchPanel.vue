<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass, message } from './definitions';
import ReviewedCadencePanel from './ReviewedCadencePanel.vue';
import DistributionComparison from './DistributionComparison.vue';
import DistributionCapacitySummary from './DistributionCapacitySummary.vue';
import ResponsibilityComparison from './ResponsibilityComparison.vue';
import { intent } from 'dashboard/routes/dashboard/approvals/model';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  actorId: { type: [String, Number], default: null },
  authorizationKey: { type: String, default: '' },
  proposal: { type: Object, default: null },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const review = ref(null);
const error = ref('');
const busy = ref(false);
const reading = ref(false);
const uncertain = ref(false);
const executionConfirmed = ref(false);
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
const storageKey = () =>
  `relationship-reviewed-batch:${props.accountId}:${props.actorId ?? 'operator'}`;
const stateLabel = state => t(`RELATIONSHIP.REVIEWED_BATCH.STATES.${state}`);
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
};
const remember = value => {
  if (review.value?.id === value.id && review.value.revision > value.revision)
    return;
  const previous = review.value;
  if (
    JSON.stringify([previous?.id, previous?.digest, previous?.approval]) !==
    JSON.stringify([value.id, value.digest, value.approval])
  )
    executionConfirmed.value = false;
  review.value = value;
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
async function refresh() {
  let id = review.value?.id;
  try {
    id ||= Number(sessionStorage.getItem(storageKey()));
  } catch {
    /* No cached operation. */
  }
  if (!Number.isSafeInteger(id) || id < 1 || reading.value) return;
  const version = epoch;
  const accountId = props.accountId;
  reading.value = true;
  try {
    const { data } = await API.portfolioBatchReview(accountId, id, {
      signal: controller.signal,
    });
    if (version === epoch) {
      remember(data);
      uncertain.value = false;
      error.value = '';
    }
  } catch (failure) {
    if (version === epoch)
      error.value = message(failure) || t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
  } finally {
    if (version === epoch) reading.value = false;
  }
}
async function mutate(action) {
  if (busy.value || !review.value) return;
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
    }
  } finally {
    if (version === epoch) busy.value = false;
  }
}
watch(
  () => props.proposal,
  async proposal => {
    if (!proposal) {
      if (!review.value || review.value.state === 'previewed') reset();
      return;
    }
    reset();
    const version = epoch;
    const accountId = props.accountId;
    busy.value = true;
    try {
      const { data } = await API.previewPortfolioBatch(accountId, proposal, {
        signal: controller.signal,
      });
      if (version === epoch) remember(data);
    } catch (failure) {
      if (version === epoch)
        error.value =
          message(failure) || t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
    } finally {
      if (version === epoch) busy.value = false;
    }
  },
  { immediate: true, deep: true }
);
watch(
  [() => props.accountId, () => props.actorId, () => props.authorizationKey],
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
        v-if="review.distribution"
        :rows="review.distribution"
      />
      <DistributionCapacitySummary :rows="review.capacity || []" />
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
          >#{{ request.id }} · {{ request.state }}</RouterLink
        >
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
          {{ item.label }} · {{ stateLabel(item.state) }}
          <span
            v-if="item.error_code"
            class="block"
          >
            {{ t('RELATIONSHIP.REVIEWED_BATCH.ITEM_FAILED') }}
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
          :disabled="busy || uncertain"
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
