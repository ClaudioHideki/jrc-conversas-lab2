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
  let scope;
  async function load({ background = false } = {}) {
    epoch += 1;
    const turn = epoch;
    controller?.abort();
    if (!enabled()) {
      result.value = null;
      scope = null;
      status.value = 'idle';
      return;
    }
    const context = session.state.context;
    if (
      session.state.status !== 'ready' ||
      context?.capabilities?.reports?.index !== true
    ) {
      result.value = null;
      scope = null;
      status.value =
        session.state.status === 'ready' ? 'denied' : session.state.status;
      return;
    }
    controller = new AbortController();
    try {
      const filters = normalizeQuery(query());
      const key = JSON.stringify(filters);
      const retain =
        background &&
        scope?.context === context &&
        scope.key === key &&
        status.value === 'ready' &&
        result.value !== null;
      scope = { context, key };
      if (!retain) {
        result.value = null;
        status.value = 'loading';
      }
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
      if (turn === epoch && context === session.state.context) {
        result.value = null;
        scope = null;
        status.value = errorStatus(error);
      }
    }
  }
  watch(
    [query, enabled, () => session.state.context, () => session.state.status],
    () => load(),
    { immediate: true, flush: 'sync' }
  );
  watch(
    () => session.operations?.state.revision,
    () => load({ background: true })
  );
  onBeforeUnmount(() => {
    epoch += 1;
    controller?.abort();
    scope = null;
    result.value = null;
  });
  return { result, status, load };
}
