<script setup>
import { onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass } from './definitions';
import ReviewedCadencePanel from './ReviewedCadencePanel.vue';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  actorId: { type: [String, Number], default: null },
  proposal: { type: Object, default: null },
});
const emit = defineEmits(['updated']);
const { t } = useI18n();
const review = ref(null);
const error = ref('');
const busy = ref(false);
const reading = ref(false);
const uncertain = ref(false);
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
};
const remember = value => {
  if (review.value?.id === value.id && review.value.revision > value.revision)
    return;
  const previous = review.value;
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
  } catch {
    if (version === epoch) error.value = t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
  } finally {
    if (version === epoch) reading.value = false;
  }
}
async function mutate(action) {
  if (busy.value || !review.value) return;
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
    if (action === 'approve')
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
  } catch {
    if (version === epoch) {
      error.value = t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
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
    } catch {
      if (version === epoch)
        error.value = t('RELATIONSHIP.REVIEWED_BATCH.ERROR');
    } finally {
      if (version === epoch) busy.value = false;
    }
  },
  { immediate: true, deep: true }
);
watch([() => props.accountId, () => props.actorId], reset);
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
          :disabled="busy || uncertain"
          @click="mutate('approve')"
        >
          {{ t('RELATIONSHIP.REVIEWED_BATCH.APPROVE') }}
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
