<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import ReviewedPortfolioBatchPanel from './ReviewedPortfolioBatchPanel.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({
  group: { type: Object, required: true },
  proposal: { type: Object, default: null },
});
const emit = defineEmits(['updated', 'proposal']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const proposal = ref(props.proposal);
const reviewed = ref(null);
const reason = ref('');
const busy = ref(false);
const blocked = ref(false);
const error = ref('');
const previewRejected = ref(false);
const unresolved = computed(() => {
  if (previewRejected.value && proposal.value) return proposal.value.ids;
  if (!['attention', 'canceled'].includes(reviewed.value?.state)) return [];
  return reviewed.value.items
    .filter(item => ['failed', 'canceled'].includes(item.state))
    .map(item => item.assignment_id);
});
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.group.id,
    props.group.can_manage,
    store.getters.getCurrentUserID,
    store.getters.getCurrentRole,
    store.getters.getCurrentUser?.accounts,
  ])
);
let generation = 0;
let controller;
const reReview = async () => {
  if (
    busy.value ||
    blocked.value ||
    !props.group.can_manage ||
    props.group.status !== 'active' ||
    !unresolved.value.length ||
    !reason.value.trim()
  )
    return;
  const token = generation;
  const previous = reviewed.value;
  const active = previous ? previous.inputs.active : proposal.value.active;
  const ids = [...unresolved.value];
  controller?.abort();
  controller = new AbortController();
  busy.value = true;
  error.value = '';
  try {
    const { data } = await API.portfolioGroup(
      route.params.accountId,
      props.group.id,
      { signal: controller.signal }
    );
    if (token !== generation) return;
    if (
      data.id !== props.group.id ||
      !data.can_manage ||
      data.status !== 'active' ||
      !Number.isSafeInteger(data.version) ||
      data.version < 0
    ) {
      blocked.value = true;
      throw new Error(t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.FRESH_BLOCKED'));
    }
    proposal.value = {
      operation: 'portfolio_membership',
      ids,
      portfolio_group_id: data.id,
      expected_version: data.version,
      active,
      ...(previous ? { previous_review_id: previous.id } : {}),
      justification: reason.value.trim(),
      request_id: crypto.randomUUID(),
    };
    emit('proposal', proposal.value);
    reviewed.value = null;
    previewRejected.value = false;
    reason.value = '';
  } catch (failure) {
    if (token !== generation) return;
    error.value = message(failure);
    if ([401, 403, 404].includes(failure.response?.status))
      blocked.value = true;
  } finally {
    if (token === generation) busy.value = false;
  }
};
watch(
  () => props.proposal,
  value => {
    proposal.value = value;
    reviewed.value = null;
    reason.value = '';
    previewRejected.value = false;
  }
);
watch(identity, () => {
  generation += 1;
  controller?.abort();
  proposal.value = null;
  reviewed.value = null;
  reason.value = '';
  busy.value = false;
  blocked.value = false;
  error.value = '';
  previewRejected.value = false;
});
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
});
</script>

<template>
  <section
    class="min-w-0 space-y-3 rounded-xl border border-n-violet-6 bg-n-solid-2 p-4"
  >
    <h3 class="font-semibold">
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11">
      {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.HELP') }}
    </p>
    <p
      v-if="error"
      role="alert"
      class="break-words text-n-ruby-11"
    >
      {{ error }}
    </p>
    <ReviewedPortfolioBatchPanel
      v-if="group.can_manage && !blocked"
      :account-id="route.params.accountId"
      :actor-id="store.getters.getCurrentUserID"
      :authorization-key="identity"
      :portfolio-group-id="group.id"
      :can-execute="group.status === 'active' && !busy"
      :proposal="proposal"
      @reviewed="reviewed = $event"
      @access-denied="blocked = true"
      @preview-failed="
        previewRejected = [409, 422].includes($event);
        blocked = [401, 403, 404].includes($event);
      "
      @updated="emit('updated')"
    />
    <form
      v-if="!blocked && unresolved.length && group.status === 'active'"
      class="space-y-3"
      @submit.prevent="reReview"
    >
      <p class="text-sm">
        {{
          t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.UNRESOLVED', {
            count: unresolved.length,
          })
        }}
      </p>
      <label class="block text-sm">
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.NEW_REASON') }}
        <textarea
          v-model="reason"
          :class="inputClass"
          required
          maxlength="4000"
          :disabled="busy"
        />
      </label>
      <button
        type="submit"
        :class="buttonClass"
        :disabled="busy || !reason.trim()"
      >
        {{ t('RELATIONSHIP.NAMED_PORTFOLIOS.BATCH.REVIEW_REMAINING') }}
      </button>
    </form>
  </section>
</template>
