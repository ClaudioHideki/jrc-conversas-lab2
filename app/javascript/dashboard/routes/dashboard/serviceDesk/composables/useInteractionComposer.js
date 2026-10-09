import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/serviceDeskCockpit';
import { useServiceDesk } from './useServiceDesk';
import { decodeCockpit } from '../helpers/cockpitContract';
import { newRequestKey } from '../helpers/drafts';
import { decodeComposer } from '../helpers/communicationContract';

export function useInteractionComposer(props, emit) {
  const session = useServiceDesk();
  const body = ref('');
  const audience = ref('internal');
  const files = ref([]);
  const destinations = ref({});
  const channels = ref({});
  const reason = ref('');
  const options = ref(null);
  const preview = ref(null);
  const busy = ref(false);
  const feedback = ref(null);
  let epoch = 0;
  let controller;
  const requestKeys = new Map();
  const active = () =>
    session.state.status === 'ready' &&
    session.state.context?.account_id === props.ticket.account_id;
  const note = computed(() => {
    const selected =
      audience.value === 'customer'
        ? Object.keys(channels.value).filter(key => channels.value[key])
        : [];
    return {
      body: body.value,
      visibility: audience.value,
      ...(audience.value === 'technical_team'
        ? { audience_team_id: props.ticket.team.id }
        : {}),
      notification_channels: selected,
      notification_conversations: Object.fromEntries(
        selected.map(key => [key, destinations.value[key]])
      ),
      ...(props.previous
        ? {
            previous_note_id: props.previous.id,
            publication_reason: reason.value,
          }
        : {}),
    };
  });
  const fingerprint = computed(() =>
    JSON.stringify({
      note: note.value,
      files: files.value.map(file => [file.name, file.size, file.lastModified]),
    })
  );
  const valid = computed(
    () =>
      body.value.trim() &&
      files.value.length <= 5 &&
      (!props.previous || reason.value.trim()) &&
      note.value.notification_channels.every(
        channel => destinations.value[channel]
      )
  );
  const scoped = payload =>
    payload.contract_version === 1 &&
    payload.account_id === props.ticket.account_id;
  const load = async () => {
    epoch += 1;
    const turn = epoch;
    controller?.abort();
    controller = new AbortController();
    options.value = null;
    if (!active()) return;
    const context = session.state.context;
    try {
      const result = await API.composer(
        context.account_id,
        props.ticket.id,
        controller.signal
      );
      if (turn !== epoch || context !== session.state.context || !active())
        return;
      options.value = decodeComposer(result, context, props.ticket);
    } catch (error) {
      if (turn === epoch) feedback.value = 'unavailable';
    }
  };
  const reset = () => {
    body.value = props.previous?.body || '';
    audience.value = 'internal';
    files.value = [];
    reason.value = '';
    destinations.value = {};
    channels.value = {};
    preview.value = null;
    requestKeys.clear();
    load();
  };
  watch(
    [
      () => props.ticket.id,
      () => props.ticket.lock_version,
      () => session.state.context,
      () => session.state.status,
      () => props.previous,
    ],
    reset,
    { immediate: true }
  );
  watch(fingerprint, () => {
    preview.value = null;
  });
  watch(audience, () => {
    channels.value = {};
    destinations.value = {};
  });
  const review = async () => {
    if (!active() || busy.value || !valid.value) return;
    busy.value = true;
    const original = fingerprint.value;
    const context = session.state.context;
    const turn = epoch;
    try {
      const result = await API.preview(
        context.account_id,
        props.ticket.id,
        note.value,
        files.value,
        controller.signal
      );
      if (
        context !== session.state.context ||
        turn !== epoch ||
        original !== fingerprint.value ||
        !active()
      )
        return;
      if (
        !scoped(result) ||
        result.preview.ticket_id !== props.ticket.id ||
        result.preview.body !== body.value ||
        result.preview.audience !== audience.value
      )
        throw new Error('Preview changed');
      preview.value = result.preview;
      feedback.value = null;
    } catch (error) {
      if (context === session.state.context && active())
        feedback.value = 'preview_invalid';
    } finally {
      busy.value = false;
    }
  };
  const submit = async () => {
    if (
      !active() ||
      busy.value ||
      !preview.value?.receipt ||
      Date.parse(preview.value.expires_at) <= Date.now()
    )
      return;
    busy.value = true;
    const context = session.state.context;
    const ticket = props.ticket;
    const submitted = note.value;
    const original = fingerprint.value;
    const approved = preview.value;
    const turn = epoch;
    if (!requestKeys.has(original)) requestKeys.set(original, newRequestKey());
    try {
      const ack = await API.interaction(
        context.account_id,
        ticket.id,
        submitted,
        files.value,
        requestKeys.get(original),
        controller.signal,
        approved.receipt
      );
      if (
        turn !== epoch ||
        !active() ||
        context !== session.state.context ||
        ticket.id !== props.ticket.id
      )
        return;
      if (
        !scoped(ack) ||
        ack.applied !== true ||
        ack.ticket_id !== ticket.id ||
        ack.operation !== 'add_interaction'
      )
        throw new Error('Invalid acknowledgement');
      const result = await API.read(
        context.account_id,
        ticket.id,
        controller.signal
      );
      if (
        turn !== epoch ||
        !active() ||
        context !== session.state.context ||
        ticket.id !== props.ticket.id
      )
        return;
      const actual = decodeCockpit(result, context, ticket).notes.find(
        row => row.id === ack.result_id
      );
      if (
        !actual ||
        actual.body !== submitted.body ||
        actual.visibility !== submitted.visibility
      )
        throw new Error('Readback unavailable');
      requestKeys.delete(original);
      reset();
      feedback.value = actual.deliveries.some(row => row.state === 'blocked')
        ? 'published_blocked'
        : 'saved';
      emit('updated', {
        operation: 'add_interaction',
        account_id: context.account_id,
        unit_id: ticket.unit_id,
        ticket_id: ticket.id,
        result_id: actual.id,
        outcome: feedback.value,
      });
    } catch (error) {
      if (context !== session.state.context || !active()) return;
      const code = error?.response?.data?.code;
      feedback.value =
        code === 'preview_invalid' ? 'preview_invalid' : 'uncertain';
      if (code === 'preview_invalid') preview.value = null;
      if ([401, 403].includes(error?.response?.status)) {
        options.value = null;
        preview.value = null;
        body.value = '';
        feedback.value = 'denied';
      }
    } finally {
      busy.value = false;
    }
  };
  onBeforeUnmount(() => {
    epoch += 1;
    controller?.abort();
    options.value = null;
    preview.value = null;
    requestKeys.clear();
  });
  return {
    body,
    audience,
    files,
    destinations,
    channels,
    reason,
    options,
    preview,
    busy,
    feedback,
    valid,
    review,
    submit,
  };
}
