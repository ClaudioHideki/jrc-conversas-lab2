import { computed, onBeforeUnmount, watch } from 'vue';
import { useServiceDesk } from './useServiceDesk';

// A local request guard, not an authorization source. Backend policies decide.
export function useOperationalScope(unitId, permits) {
  const session = useServiceDesk();
  let generation = 0;
  let controller;
  const identity = computed(() => {
    const context = session.state.context;
    return JSON.stringify([
      session.state.status,
      context?.account_id,
      context?.user_id,
      context?.units,
      context?.capabilities,
    ]);
  });
  const allowed = computed(
    () =>
      session.state.status === 'ready' &&
      permits(session.state.context) === true &&
      session.state.context.units.some(unit => unit.id === unitId.value)
  );
  const cancel = () => {
    generation += 1;
    controller?.abort();
  };
  watch([identity, unitId], cancel, { flush: 'sync' });
  onBeforeUnmount(cancel);
  const begin = () => {
    cancel();
    if (!allowed.value) return null;
    controller = new AbortController();
    return {
      generation,
      identity: identity.value,
      unit: unitId.value,
      context: session.state.context,
      signal: controller.signal,
    };
  };
  const live = lease =>
    !!lease &&
    allowed.value &&
    lease.generation === generation &&
    lease.identity === identity.value &&
    lease.unit === unitId.value;
  return { session, identity, allowed, begin, live, cancel };
}
