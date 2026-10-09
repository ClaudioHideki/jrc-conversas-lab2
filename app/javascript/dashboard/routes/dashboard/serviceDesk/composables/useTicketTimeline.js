import { onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/serviceDeskCockpit';
import { useServiceDesk } from './useServiceDesk';
import { decodeTimeline } from '../helpers/communicationContract';
import { errorStatus } from '../helpers/session';

export function useTicketTimeline(props) {
  const session = useServiceDesk();
  const items = ref([]);
  const cursor = ref(null);
  const status = ref('loading');
  const busy = ref(false);
  let epoch = 0;
  let controller;
  const active = () =>
    session.state.status === 'ready' &&
    session.state.context?.account_id === props.ticket.account_id;
  const load = async (append = false) => {
    if (busy.value && append) return;
    if (!append) {
      epoch += 1;
      controller?.abort();
      items.value = [];
      cursor.value = null;
    }
    if (!active()) {
      items.value = [];
      status.value = 'denied';
      return;
    }
    const turn = epoch;
    const context = session.state.context;
    controller = new AbortController();
    busy.value = true;
    try {
      const response = await API.timeline(
        context.account_id,
        props.ticket.id,
        append ? cursor.value : null,
        controller.signal
      );
      if (turn !== epoch || context !== session.state.context || !active())
        return;
      const page = decodeTimeline(response, context, props.ticket);
      const all = append ? [...items.value, ...page.items] : page.items;
      items.value = [...new Map(all.map(row => [row.key, row])).values()];
      cursor.value = page.cursor;
      status.value = items.value.length ? 'ready' : 'empty';
    } catch (error) {
      if (turn !== epoch || context !== session.state.context) return;
      items.value = [];
      cursor.value = null;
      status.value = errorStatus(error);
    } finally {
      if (turn === epoch) busy.value = false;
    }
  };
  watch(
    [
      () => props.ticket.id,
      () => props.ticket.lock_version,
      () => session.state.context,
      () => session.state.status,
      () => props.revision,
    ],
    () => load(),
    { immediate: true }
  );
  onBeforeUnmount(() => {
    epoch += 1;
    controller?.abort();
    items.value = [];
    cursor.value = null;
  });
  return { items, cursor, status, busy, load };
}
