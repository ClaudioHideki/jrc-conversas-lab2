<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { buttonClass, inputClass, message } from './definitions';
const props = defineProps({ analystId: { type: Number, required: true } });
const emit = defineEmits(['close']);
const route = useRoute();
const store = useStore();
const { t } = useI18n();
const dialog = ref(null);
const result = ref(null);
const error = ref(false);
const busy = ref(false);
const reason = ref('');
const acknowledged = ref(false);
const submitError = ref('');
const restored = ref(false);
const restoring = computed(
  () =>
    result.value?.relationship_withdrawn_at &&
    result.value?.can_restore_relationship &&
    Number.isSafeInteger(result.value?.eligibility_version)
);
const canDecide = computed(
  () =>
    restoring.value ||
    (!result.value?.relationship_withdrawn_at &&
      result.value?.can_withdraw_relationship &&
      !restored.value)
);
const identity = computed(() =>
  JSON.stringify([
    route.params.accountId,
    props.analystId,
    store.getters.getCurrentUser,
    store.getters.getCurrentRole,
  ])
);
let generation = 0;
let controller;
const clear = () => {
  generation += 1;
  controller?.abort();
  result.value = null;
  busy.value = false;
  reason.value = '';
  acknowledged.value = false;
  submitError.value = '';
  restored.value = false;
};
const decideEligibility = async () => {
  if (
    busy.value ||
    !canDecide.value ||
    !acknowledged.value ||
    !reason.value.trim() ||
    reason.value.length > 4000
  ) {
    return;
  }
  const token = generation;
  busy.value = true;
  submitError.value = '';
  const restore = restoring.value;
  try {
    const fields = restore
      ? {
          reason: reason.value.trim(),
          expected_version: result.value.eligibility_version,
        }
      : {
          reason: reason.value.trim(),
          snapshot_digest: result.value.snapshot_digest,
        };
    const request = restore ? API.restoreAnalyst : API.withdrawAnalyst;
    const { data } = await request(
      route.params.accountId,
      props.analystId,
      fields,
      { signal: controller.signal }
    );
    if (token === generation) {
      result.value = {
        ...result.value,
        can_withdraw_relationship: false,
        can_restore_relationship: false,
        relationship_withdrawn_at: restore ? null : data.withdrawn_at,
        eligibility_version: data.eligibility_version,
      };
      restored.value = !!restore;
    }
  } catch (err) {
    if (token === generation) {
      if ([403, 404].includes(err.response?.status)) {
        clear();
        emit('close');
      } else {
        submitError.value = message(err);
      }
    }
  } finally {
    if (token === generation) busy.value = false;
  }
};
const load = async () => {
  clear();
  const token = generation;
  controller = new AbortController();
  error.value = false;
  try {
    const { data } = await API.withdrawalReadiness(
      route.params.accountId,
      props.analystId,
      { signal: controller.signal }
    );
    if (token === generation) result.value = data;
  } catch {
    if (token === generation) error.value = true;
  }
};
watch(identity, () => {
  clear();
  emit('close');
});
onMounted(() => {
  dialog.value.open();
  load();
});
onBeforeUnmount(clear);
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('RELATIONSHIP.WITHDRAWAL.TITLE')"
    :description="t('RELATIONSHIP.WITHDRAWAL.NOTE')"
    :show-confirm-button="false"
    :use-form="false"
    show-close-button
    width="xl"
    @close="emit('close')"
  >
    <p
      v-if="error"
      role="alert"
      class="text-n-ruby-11"
    >
      {{ t('RELATIONSHIP.WITHDRAWAL.UNAVAILABLE') }}
    </p>
    <p
      v-else-if="!result"
      role="status"
    >
      {{ t('RELATIONSHIP.LOADING') }}
    </p>
    <section
      v-if="result"
      class="min-w-0 space-y-3"
    >
      <p class="rounded-lg bg-n-amber-3 p-3 text-sm text-n-amber-12">
        {{ t(`RELATIONSHIP.WITHDRAWAL.${result.state}`) }}
      </p>
      <dl class="grid gap-3 sm:grid-cols-2">
        <div
          v-for="(count, kind) in result.counts"
          :key="kind"
          class="rounded-lg border border-n-weak p-3"
        >
          <dt class="text-sm">
            {{ t(`RELATIONSHIP.WITHDRAWAL.KINDS.${kind}`) }}
          </dt>
          <dd class="font-bold">{{ count }}</dd>
        </div>
      </dl>
      <p
        v-if="result.counts?.reviewed_batches > 0"
        class="rounded-lg border border-n-violet-6 bg-n-violet-2 p-3 text-sm text-n-violet-11"
      >
        {{ t('RELATIONSHIP.WITHDRAWAL.REVIEWED_OPERATIONS_HELP') }}
      </p>
      <p class="text-sm text-n-slate-11">
        {{ t('RELATIONSHIP.WITHDRAWAL.FINAL_REVIEW') }}
      </p>
      <p
        v-if="restored"
        role="status"
        class="rounded-lg bg-n-teal-3 p-3 text-sm text-n-teal-12"
      >
        {{ t('RELATIONSHIP.WITHDRAWAL.RESTORED') }}
      </p>
      <p
        v-else-if="result.relationship_withdrawn_at"
        role="status"
        class="rounded-lg bg-n-teal-3 p-3 text-sm text-n-teal-12"
      >
        {{ t('RELATIONSHIP.WITHDRAWAL.WITHDRAWN') }}
      </p>
      <form
        v-if="canDecide"
        class="min-w-0 space-y-3 rounded-lg border border-n-weak p-3"
        data-testid="withdrawal-confirmation"
        @submit.prevent="decideEligibility"
      >
        <label class="block text-sm">
          {{ t('RELATIONSHIP.WITHDRAWAL.REASON') }}
          <textarea
            v-model="reason"
            :class="inputClass"
            :disabled="busy"
            maxlength="4000"
            rows="3"
            required
          />
        </label>
        <label class="flex items-start gap-2 text-sm">
          <input
            v-model="acknowledged"
            type="checkbox"
            :disabled="busy"
            required
          />
          <span v-if="restoring">{{
            t('RELATIONSHIP.WITHDRAWAL.RESTORE_SCOPE')
          }}</span>
          <span v-else>{{ t('RELATIONSHIP.WITHDRAWAL.CONFIRM_SCOPE') }}</span>
        </label>
        <p
          v-if="submitError"
          role="alert"
          class="break-words text-n-ruby-11"
        >
          {{ submitError }}
        </p>
        <button
          type="submit"
          :class="buttonClass"
          :disabled="
            busy || !acknowledged || !reason.trim() || reason.length > 4000
          "
        >
          <span v-if="restoring">{{
            t('RELATIONSHIP.WITHDRAWAL.RESTORE')
          }}</span>
          <span v-else>{{ t('RELATIONSHIP.WITHDRAWAL.WITHDRAW') }}</span>
        </button>
        <button
          v-if="submitError"
          type="button"
          :class="buttonClass"
          :disabled="busy"
          @click="load"
        >
          {{ t('RELATIONSHIP.REFRESH') }}
        </button>
      </form>
      <button
        v-if="result.relationship_withdrawn_at || restored"
        type="button"
        :class="buttonClass"
        :disabled="busy"
        data-testid="eligibility-refresh"
        @click="load"
      >
        {{ t('RELATIONSHIP.WITHDRAWAL.REVIEW_CURRENT') }}
      </button>
    </section>
  </Dialog>
</template>
