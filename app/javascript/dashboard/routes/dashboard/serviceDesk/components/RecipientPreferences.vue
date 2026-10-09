<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/serviceDeskCockpit';
import { useServiceDesk } from '../composables/useServiceDesk';
import { communicationLabels } from '../helpers/communicationLabels';
import { v2Labels } from '../helpers/v2Labels';

const props = defineProps({ ticket: { type: Object, required: true } });
const emit = defineEmits(['updated']);
const session = useServiceDesk();
const { t } = useI18n();
const labels = computed(() => communicationLabels(t));
const values = computed(() => v2Labels(t));
const channels = ref([]);
const busy = ref(false);
const ready = ref(false);
const feedback = ref('');
const allowed = computed(
  () =>
    session.state.status === 'ready' &&
    session.state.context?.capabilities?.notifications?.manage === true &&
    props.ticket.permissions?.view_customer === true
);
let generation = 0;
let controller;
const active = (context, turn) =>
  allowed.value && context === session.state.context && turn === generation;
const decode = (payload, context, ticket) => {
  if (
    payload.contract_version !== 1 ||
    payload.account_id !== context.account_id ||
    payload.ticket_id !== ticket.id ||
    !Array.isArray(payload.channels) ||
    new Set(payload.channels).size !== payload.channels.length ||
    payload.channels.some(channel => !['email', 'whatsapp'].includes(channel))
  )
    throw new TypeError('Invalid recipient preferences');
  return [...payload.channels];
};
const load = async () => {
  generation += 1;
  const turn = generation;
  controller?.abort();
  channels.value = [];
  ready.value = false;
  feedback.value = '';
  if (!allowed.value) return;
  controller = new AbortController();
  const context = session.state.context;
  const ticket = props.ticket;
  try {
    const result = await API.recipientPreferences(
      context.account_id,
      ticket.id,
      controller.signal
    );
    if (!active(context, turn)) return;
    channels.value = decode(result, context, ticket);
    ready.value = true;
  } catch {
    if (active(context, turn)) feedback.value = 'unavailable';
  }
};
watch([() => props.ticket.id, () => session.state.context, allowed], load, {
  immediate: true,
});
const save = async () => {
  if (!allowed.value || !ready.value || busy.value) return;
  const context = session.state.context;
  const ticket = props.ticket;
  const selected = [...channels.value].sort();
  const turn = generation;
  busy.value = true;
  try {
    const ack = await API.updateRecipientPreferences(
      context.account_id,
      ticket.id,
      selected,
      controller.signal
    );
    if (!active(context, turn)) return;
    const result = decode(
      await API.recipientPreferences(
        context.account_id,
        ticket.id,
        controller.signal
      ),
      context,
      ticket
    );
    if (!active(context, turn)) return;
    if (
      !ack.applied ||
      JSON.stringify(decode(ack, context, ticket).sort()) !==
        JSON.stringify(selected) ||
      JSON.stringify(result.sort()) !== JSON.stringify(selected)
    )
      throw new TypeError('Unverified preferences');
    channels.value = result;
    feedback.value = 'saved';
    emit('updated');
  } catch {
    if (active(context, turn)) {
      ready.value = false;
      feedback.value = 'uncertain';
    }
  } finally {
    busy.value = false;
  }
};
onBeforeUnmount(() => {
  generation += 1;
  controller?.abort();
  channels.value = [];
});
</script>

<template>
  <form
    v-if="allowed"
    class="grid gap-2 rounded-lg border border-n-weak p-3"
    @submit.prevent="save"
  >
    <h4 class="text-sm font-medium">
      {{ t('JRC_SERVICE_DESK.R3.recipient_preferences') }}
    </h4>
    <p class="text-xs text-n-slate-11">
      {{ t('JRC_SERVICE_DESK.R3.preferences_help') }}
    </p>
    <label
      v-for="channel in ['email', 'whatsapp']"
      :key="channel"
      class="flex gap-2 text-sm"
    >
      <input
        v-model="channels"
        type="checkbox"
        :value="channel"
        :disabled="busy || !ready"
      />
      {{ values.channel[channel] }}
    </label>
    <Button
      type="submit"
      size="xs"
      :disabled="busy || !ready"
      :label="t('JRC_SERVICE_DESK.COMMON.save')"
    />
    <Button
      type="button"
      size="xs"
      variant="outline"
      :disabled="busy"
      :label="t('JRC_SERVICE_DESK.COMMON.refresh')"
      @click="load"
    />
    <p v-if="feedback" role="status" class="text-sm">{{ labels[feedback] }}</p>
  </form>
</template>
