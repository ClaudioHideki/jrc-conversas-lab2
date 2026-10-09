<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import API from 'dashboard/api/serviceDeskCockpit';
import { useServiceDesk } from '../composables/useServiceDesk';
import { communicationLabels } from '../helpers/communicationLabels';
import { decodeTimeline } from '../helpers/communicationContract';
import { newRequestKey } from '../helpers/drafts';

const props = defineProps({
  row: { type: Object, required: true },
  ticket: { type: Object, required: true },
});
const emit = defineEmits(['updated']);
const session = useServiceDesk();
const { t } = useI18n();
const labels = computed(() => communicationLabels(t));
const reason = ref('');
const preview = ref(null);
const busy = ref(false);
const feedback = ref(null);
let key;
let generation = 0;
watch(
  [
    reason,
    () => props.row,
    () => session.state.context,
    () => session.state.status,
  ],
  () => {
    generation += 1;
    preview.value = null;
    key = null;
  }
);
const active = context =>
  context === session.state.context &&
  session.state.status === 'ready' &&
  context.account_id === props.ticket.account_id;
const review = async () => {
  if (busy.value || !reason.value.trim()) return;
  const context = session.state.context;
  const turn = generation;
  busy.value = true;
  try {
    const payload = await API.resendPreview(
      context.account_id,
      props.ticket.id,
      props.row.id,
      reason.value
    );
    if (!active(context) || turn !== generation) return;
    const row = payload.preview;
    if (
      payload.account_id !== context.account_id ||
      row.ticket_id !== props.ticket.id ||
      row.delivery_id !== props.row.id ||
      row.reason !== reason.value
    )
      throw new Error('Invalid preview');
    preview.value = row;
    key ||= newRequestKey();
  } catch (error) {
    if (active(context)) feedback.value = 'preview_invalid';
  } finally {
    busy.value = false;
  }
};
const resend = async () => {
  if (
    busy.value ||
    !preview.value?.available ||
    Date.parse(preview.value.expires_at) <= Date.now()
  )
    return;
  const context = session.state.context;
  const approved = preview.value;
  const turn = generation;
  busy.value = true;
  try {
    const ack = await API.resend(
      context.account_id,
      props.ticket.id,
      props.row.id,
      reason.value,
      approved.receipt,
      key
    );
    if (!active(context) || turn !== generation) return;
    if (
      !ack.applied ||
      ack.account_id !== context.account_id ||
      ack.ticket_id !== props.ticket.id ||
      ack.operation !== 'resend_notification'
    )
      throw new Error('Invalid acknowledgement');
    const page = decodeTimeline(
      await API.timeline(context.account_id, props.ticket.id),
      context,
      props.ticket
    );
    if (!active(context) || turn !== generation) return;
    const actual = page.items.find(
      row => row.kind === 'delivery' && row.id === ack.result_id
    );
    if (
      !actual ||
      actual.original_delivery_id !== props.row.id ||
      actual.recipient !== approved.recipient ||
      actual.content !== approved.content
    )
      throw new Error('Unverified resend');
    feedback.value = 'saved';
    preview.value = null;
    reason.value = '';
    emit('updated');
  } catch (error) {
    if (active(context)) {
      feedback.value = 'uncertain';
      preview.value = null;
    }
  } finally {
    busy.value = false;
  }
};
const reconcile = async () => {
  if (busy.value) return;
  const context = session.state.context;
  busy.value = true;
  try {
    const response = await API.reconcile(
      context.account_id,
      props.ticket.id,
      props.row.id
    );
    if (!active(context)) return;
    if (
      response.account_id !== context.account_id ||
      response.ticket_id !== props.ticket.id ||
      response.delivery.id !== props.row.id
    )
      throw new Error('Unverified receipt');
    emit('updated');
  } catch (error) {
    if (active(context)) feedback.value = 'uncertain';
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <section class="grid gap-2">
    <Button
      v-if="row.permissions.reconcile"
      size="xs"
      variant="outline"
      :disabled="busy"
      :label="labels.reconcile"
      @click="reconcile"
    />
    <template v-if="row.permissions.resend">
      <input
        v-model="reason"
        maxlength="2000"
        :disabled="busy"
        :aria-label="labels.resend_reason"
        :placeholder="labels.resend_reason"
        class="rounded-lg border border-n-weak bg-n-solid-1 p-2 text-sm"
      />
      <Button
        size="xs"
        variant="outline"
        :disabled="busy || !reason.trim()"
        :label="labels.resend"
        @click="review"
      />
      <section
        v-if="preview"
        class="grid gap-2 rounded-lg border border-n-weak p-3"
      >
        <p class="text-sm">{{ preview.recipient }}</p>
        <p class="whitespace-pre-wrap text-sm">{{ preview.content }}</p>
        <p v-if="preview.unavailable_reason" class="text-sm">
          {{ labels.reasons[preview.unavailable_reason] || labels.unavailable }}
        </p>
        <Button
          size="xs"
          :disabled="busy || !preview.available"
          :label="labels.confirm_resend"
          @click="resend"
        />
      </section>
    </template>
    <p v-if="feedback" role="status" class="text-sm">{{ labels[feedback] }}</p>
  </section>
</template>
