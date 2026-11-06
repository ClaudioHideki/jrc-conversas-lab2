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
};
const withdraw = async () => {
  if (
    busy.value ||
    !result.value?.can_withdraw_relationship ||
    !acknowledged.value ||
    !reason.value.trim() ||
    reason.value.length > 4000
  ) {
    return;
  }
  const token = generation;
  busy.value = true;
  submitError.value = '';
  try {
    const { data } = await API.withdrawAnalyst(
      route.params.accountId,
      props.analystId,
      {
        reason: reason.value.trim(),
        snapshot_digest: result.value.snapshot_digest,
      },
      { signal: controller.signal }
    );
    if (token === generation) {
      result.value = {
        ...result.value,
        can_withdraw_relationship: false,
        relationship_withdrawn_at: data.withdrawn_at,
      };
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
      <p class="text-sm text-n-slate-11">
        {{ t('RELATIONSHIP.WITHDRAWAL.FINAL_REVIEW') }}
      </p>
      <p
        v-if="result.relationship_withdrawn_at"
        role="status"
        class="rounded-lg bg-n-teal-3 p-3 text-sm text-n-teal-12"
      >
        {{ t('RELATIONSHIP.WITHDRAWAL.WITHDRAWN') }}
      </p>
      <form
        v-else-if="result.can_withdraw_relationship"
        class="min-w-0 space-y-3 rounded-lg border border-n-weak p-3"
        data-testid="withdrawal-confirmation"
        @submit.prevent="withdraw"
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
          {{ t('RELATIONSHIP.WITHDRAWAL.CONFIRM_SCOPE') }}
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
          {{ t('RELATIONSHIP.WITHDRAWAL.WITHDRAW') }}
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
    </section>
  </Dialog>
</template>
