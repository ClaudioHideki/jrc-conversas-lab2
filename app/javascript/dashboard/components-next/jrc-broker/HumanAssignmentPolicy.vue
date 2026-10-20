<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { createJrcBrokerApi } from 'dashboard/api/jrcBroker';

const props = defineProps({
  accountId: { type: [Number, String], required: true },
});
const { t } = useI18n();
const enabled = ref(false);
const maxOpen = ref(10);
const inboxes = ref([]);
const inboxIds = ref([]);
const loaded = ref(false);
const busy = ref(false);
const feedback = ref('');
let generation = 0;
let controller;
let api;
const valid = computed(
  () =>
    Number.isInteger(maxOpen.value) &&
    maxOpen.value >= 1 &&
    maxOpen.value <= 100 &&
    (!enabled.value || inboxIds.value.length > 0)
);
const clear = () => {
  generation += 1;
  controller?.abort();
  loaded.value = false;
  busy.value = false;
  feedback.value = '';
  enabled.value = false;
  maxOpen.value = 10;
  inboxes.value = [];
  inboxIds.value = [];
};
const load = async () => {
  clear();
  const current = generation;
  controller = new AbortController();
  api = createJrcBrokerApi(props.accountId);
  busy.value = true;
  try {
    const [policy, availableInboxes] = await Promise.all([
      api.assignmentPolicy(controller.signal),
      api.inboxes(controller.signal),
    ]);
    if (current !== generation) return;
    enabled.value = policy.enabled;
    maxOpen.value = policy.max_open;
    inboxes.value = availableInboxes;
    inboxIds.value = policy.inbox_ids.filter(id =>
      availableInboxes.some(inbox => inbox.id === id)
    );
    loaded.value = true;
  } catch {
    if (current === generation) feedback.value = 'ERROR';
  } finally {
    if (current === generation) busy.value = false;
  }
};
const save = async () => {
  if (!loaded.value || busy.value || !valid.value) return;
  const current = generation;
  busy.value = true;
  feedback.value = '';
  try {
    const policy = await api.saveAssignmentPolicy(
      {
        enabled: enabled.value,
        max_open: maxOpen.value,
        inbox_ids: inboxIds.value,
      },
      controller.signal
    );
    if (current !== generation) return;
    enabled.value = policy.enabled;
    maxOpen.value = policy.max_open;
    inboxIds.value = policy.inbox_ids;
    feedback.value = 'SAVED';
  } catch {
    if (current === generation) feedback.value = 'ERROR';
  } finally {
    if (current === generation) busy.value = false;
  }
};
watch(() => props.accountId, load, { immediate: true, flush: 'sync' });
onBeforeUnmount(clear);
</script>

<template>
  <form
    class="rounded-xl border border-n-weak bg-n-solid-1 p-5"
    @submit.prevent="save"
  >
    <h2 class="text-lg font-semibold text-n-slate-12">
      {{ t('JRC_BROKER.ASSIGNMENT.TITLE') }}
    </h2>
    <p class="my-3 text-sm text-n-slate-11">
      {{ t('JRC_BROKER.ASSIGNMENT.HELP') }}
    </p>
    <fieldset :disabled="busy || !loaded" class="flex flex-col gap-4">
      <label class="flex items-center gap-2 text-sm">
        <input v-model="enabled" type="checkbox" />
        {{ t('JRC_BROKER.ASSIGNMENT.ENABLED') }}
      </label>
      <div class="flex flex-col gap-2 text-sm">
        <p>{{ t('JRC_BROKER.ASSIGNMENT.INBOXES') }}</p>
        <label
          v-for="inbox in inboxes"
          :key="inbox.id"
          class="flex items-center gap-2"
        >
          <input
            v-model="inboxIds"
            type="checkbox"
            :value="inbox.id"
            :data-inbox-id="inbox.id"
          />
          {{ inbox.name }}
        </label>
        <p v-if="!inboxes.length">
          {{ t('JRC_BROKER.ASSIGNMENT.NO_INBOXES') }}
        </p>
      </div>
      <label class="flex flex-col gap-2 text-sm">
        {{ t('JRC_BROKER.ASSIGNMENT.CAPACITY') }}
        <input
          v-model.number="maxOpen"
          type="number"
          min="1"
          max="100"
          required
        />
      </label>
      <button
        type="submit"
        :disabled="!valid"
        class="self-start rounded-lg bg-n-brand px-4 py-2 text-white disabled:opacity-50"
      >
        {{ t('JRC_BROKER.ASSIGNMENT.SAVE') }}
      </button>
    </fieldset>
    <p
      v-if="feedback"
      class="mt-3 text-sm"
      :role="feedback === 'ERROR' ? 'alert' : 'status'"
    >
      {{ t(`JRC_BROKER.ASSIGNMENT.${feedback}`) }}
    </p>
  </form>
</template>
