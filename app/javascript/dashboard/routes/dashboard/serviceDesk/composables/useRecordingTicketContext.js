import { computed, onBeforeUnmount, ref, watch } from 'vue';
import API from 'dashboard/api/jrcContactCenter';
import { canonicalId } from '../helpers/access';
import { decodeRecordingTicketSource } from '../helpers/recordingTicketSource';

// The query selects an origin, never an account, actor, permission or destination grant.
export function useRecordingTicketContext({ route, session, enabled, edit }) {
  const present = computed(
    () => !edit.value && route.query.recording_id !== undefined
  );
  const source = ref(null);
  const loading = ref(false);
  const error = ref(false);
  let controller;
  let generation = 0;
  const identity = computed(() =>
    JSON.stringify([
      session.accountId.value,
      session.userId.value,
      session.state.status,
      present.value,
      route.query.recording_id,
      enabled.value,
      session.state.context?.effective_permissions,
      session.state.context?.units.map(unit => [
        unit.id,
        unit.operator_company?.id,
        unit.permissions,
      ]),
    ])
  );
  const refresh = async () => {
    generation += 1;
    const version = generation;
    controller?.abort();
    source.value = null;
    loading.value = false;
    error.value = false;
    if (!present.value) return;
    if (!enabled.value || session.state.status !== 'ready') {
      error.value = true;
      return;
    }
    const account = session.accountId.value;
    const actor = session.userId.value;
    const recording = canonicalId(route.query.recording_id);
    if (!recording) {
      error.value = true;
      return;
    }
    const original = identity.value;
    const request = new AbortController();
    controller = request;
    loading.value = true;
    try {
      const { data } = await API.recordingTicketIntake(account, recording, {
        signal: request.signal,
      });
      if (
        version !== generation ||
        request.signal.aborted ||
        original !== identity.value
      )
        return;
      const value = decodeRecordingTicketSource(
        data,
        account,
        actor,
        recording
      );
      const unit = session.state.context?.units.find(
        row => row.id === value.service_desk_unit_id
      );
      if (unit?.permissions.create_ticket !== true)
        throw new TypeError('Native destination is not permitted');
      source.value = value;
    } catch {
      if (version === generation && !request.signal.aborted) error.value = true;
    } finally {
      if (version === generation) loading.value = false;
    }
  };
  watch(identity, refresh, { immediate: true, flush: 'pre' });
  onBeforeUnmount(() => {
    generation += 1;
    controller?.abort();
    source.value = null;
  });
  return { present, source, loading, error, refresh, identity };
}
