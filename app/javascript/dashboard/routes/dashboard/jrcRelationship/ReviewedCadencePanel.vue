<script setup>
import { onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import API from 'dashboard/api/jrcRelationship';
import { buttonClass } from './definitions';
const props = defineProps({
  accountId: { type: [String, Number], required: true },
  cadenceId: { type: Number, required: true },
});
const { t } = useI18n();
const record = ref(null);
const busy = ref(false);
const error = ref(false);
const uncertain = ref(false);
let epoch = 0;
let controller = new AbortController();
let timer;
async function request(action = 'read') {
  if (busy.value || controller.signal.aborted) return;
  busy.value = true;
  const version = epoch;
  const options = { signal: controller.signal };
  try {
    let response;
    if (action === 'advance')
      response = await API.advanceCadence(
        props.accountId,
        props.cadenceId,
        options
      );
    else if (action === 'cancel')
      response = await API.cancelCadence(
        props.accountId,
        props.cadenceId,
        options
      );
    else
      response = await API.cadence(props.accountId, props.cadenceId, options);
    if (version !== epoch) return;
    const { data } = response;
    if (
      data.id !== props.cadenceId ||
      (record.value && data.revision < record.value.revision)
    )
      return;
    record.value = data;
    error.value = false;
    uncertain.value = false;
    clearInterval(timer);
    if (data.state === 'active') timer = setInterval(() => request(), 2000);
  } catch {
    if (version === epoch) {
      error.value = true;
      uncertain.value = action !== 'read' || uncertain.value;
    }
  } finally {
    if (version === epoch) busy.value = false;
  }
}
watch(
  [() => props.accountId, () => props.cadenceId],
  () => {
    epoch += 1;
    controller.abort();
    controller = new AbortController();
    clearInterval(timer);
    record.value = null;
    busy.value = false;
    error.value = false;
    uncertain.value = false;
    request();
  },
  { immediate: true }
);
onBeforeUnmount(() => {
  epoch += 1;
  controller.abort();
  clearInterval(timer);
});
</script>

<template>
  <section
    class="mt-3 rounded-xl border border-n-weak p-3"
    aria-live="polite"
  >
    <h4>{{ t('RELATIONSHIP.REVIEWED_BATCH.CADENCE') }}</h4>
    <p
      v-if="error"
      role="alert"
    >
      {{ t('RELATIONSHIP.REVIEWED_BATCH.ERROR') }}
    </p>
    <template v-if="record">
      <p>
        {{
          t('RELATIONSHIP.REVIEWED_BATCH.BOOK', {
            name: record.book_name,
            version: record.book_version,
          })
        }}
      </p>
      <p>{{ t(`RELATIONSHIP.CADENCE.STATES.${record.state}`) }}</p>
      <p v-if="record.stop_reason">
        {{ t(`RELATIONSHIP.CADENCE.REASONS.${record.stop_reason}`) }}
      </p>
      <ul>
        <li
          v-for="step in record.steps"
          :key="step.ordinal"
          class="my-2"
        >
          <p>{{ step.title }}</p>
          <p>{{ step.due_at }}</p>
          <p>{{ t(`RELATIONSHIP.CADENCE.STATES.${step.state}`) }}</p>
        </li>
      </ul>
      <div
        v-if="record.state === 'active'"
        class="flex gap-2"
      >
        <button
          type="button"
          :class="buttonClass"
          :disabled="busy || uncertain"
          @click="request('advance')"
        >
          {{ t('RELATIONSHIP.CADENCE.ADVANCE') }}
        </button>
        <button
          type="button"
          data-test="cadence-cancel"
          :class="buttonClass"
          :disabled="busy"
          @click="request('cancel')"
        >
          {{ t('RELATIONSHIP.REVIEWED_BATCH.CANCEL') }}
        </button>
      </div>
    </template>
    <button
      type="button"
      :class="buttonClass"
      :disabled="busy"
      @click="request()"
    >
      {{ t('RELATIONSHIP.CADENCE.REFRESH') }}
    </button>
  </section>
</template>
