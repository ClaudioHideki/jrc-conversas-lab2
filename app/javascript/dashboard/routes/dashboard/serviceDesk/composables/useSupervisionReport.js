import { onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/serviceDeskOperationsV2';
import { normalizeQuery } from '../helpers/query.js';
import { decodeReport } from '../helpers/v2Projection.js';
import { errorStatus } from '../helpers/session.js';
export function useSupervisionReport(session, query, enabled = () => true) {
  const result = ref(null);
  const status = ref('idle');
  let epoch = 0;
  let controller;
  async function load() {
    epoch += 1;
    const turn = epoch;
    controller?.abort();
    result.value = null;
    if (!enabled()) {
      status.value = 'idle';
      return;
    }
    const context = session.state.context;
    if (
      session.state.status !== 'ready' ||
      context?.capabilities?.reports?.index !== true
    ) {
      status.value =
        session.state.status === 'ready' ? 'denied' : session.state.status;
      return;
    }
    controller = new AbortController();
    status.value = 'loading';
    try {
      const filters = normalizeQuery(query());
      const payload = await API.report(
        context.account_id,
        filters,
        controller.signal
      );
      if (
        turn !== epoch ||
        context !== session.state.context ||
        session.state.status !== 'ready' ||
        !enabled()
      )
        return;
      result.value = decodeReport(payload, context, filters);
      status.value = 'ready';
    } catch (error) {
      if (turn === epoch && context === session.state.context)
        status.value = errorStatus(error);
    }
  }
  watch(
    [
      query,
      enabled,
      () => session.state.context,
      () => session.state.status,
      () => session.operations?.state.revision,
    ],
    load,
    { immediate: true, flush: 'sync' }
  );
  onBeforeUnmount(() => {
    epoch += 1;
    controller?.abort();
    result.value = null;
  });
  return { result, status, load };
}
