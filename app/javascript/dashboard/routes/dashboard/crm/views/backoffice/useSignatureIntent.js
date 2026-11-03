import { computed, onBeforeUnmount, ref } from 'vue';
import api from 'dashboard/api/crm/backofficeSignatures';
import { useBackofficePresentation } from './useBackofficePresentation';

const knownCodes = new Set([
  'REQUEST_NOT_EDITABLE',
  'CONTRACT_VERSION_REQUIRED',
  'DELIVERY_IN_PROGRESS',
  'CONTRACT_SOURCE_CHANGED',
  'AUTHORITY_APPROVAL_REQUIRED',
  'CONNECTION_NOT_READY',
  'CONNECTION_CHANGED',
  'DELIVERY_ALREADY_DISPATCHED',
  'DELIVERY_INTENT_CHANGED',
  'DELIVERY_VERSION_ALREADY_REGISTERED',
]);

export function useSignatureIntent(props, emit) {
  const { text } = useBackofficePresentation();
  const preview = ref(null);
  const confirmed = ref(false);
  const loading = ref(false);
  const saving = ref(false);
  const error = ref('');
  let active = true;
  let key;
  let generation = 0;
  let controller;
  const canceling = computed(() => Boolean(props.delivery));
  const busy = computed(() => loading.value || saving.value);
  const message = code =>
    text(
      `CONTRACT_SIGNATURES.ACTION_ERRORS.${knownCodes.has(code) ? code : 'BLOCKED'}`
    );
  const available = computed(() =>
    canceling.value
      ? props.delivery.state === 'prepared'
      : preview.value?.can_send === true
  );
  const canSubmit = computed(
    () => available.value && confirmed.value && !busy.value
  );
  const denied = () => {
    preview.value = null;
    confirmed.value = false;
    emit('denied');
  };
  const load = async () => {
    generation += 1;
    const token = generation;
    controller?.abort();
    controller = new AbortController();
    preview.value = null;
    confirmed.value = false;
    error.value = '';
    if (canceling.value) return;
    loading.value = true;
    key = crypto.randomUUID();
    try {
      const { data } = await api.preparation(props.accountId, props.requestId, {
        signal: controller.signal,
      });
      if (!active || token !== generation) return;
      preview.value = data;
      if (data.can_send !== true) error.value = message(data.blocked_code);
    } catch (failure) {
      if (!active || token !== generation) return;
      if ([401, 403, 404].includes(failure.response?.status)) denied();
      else error.value = text('CONTRACT_SIGNATURES.ACTION_ERROR');
    } finally {
      if (active && token === generation) loading.value = false;
    }
  };
  const submit = async () => {
    if (!canSubmit.value) return;
    const token = generation;
    saving.value = true;
    error.value = '';
    const options = { signal: controller.signal };
    try {
      if (canceling.value) {
        await api.cancelPrepared(
          props.accountId,
          props.requestId,
          props.delivery.id,
          options
        );
      } else {
        const data = preview.value;
        await api.create(
          props.accountId,
          props.requestId,
          {
            version_id: data.version.id,
            authority_proposal_id: data.authority_proposal_id,
            expected_connection_id: data.connection.id,
            expected_source_digest: data.expected_source_digest,
            idempotency_key: key,
          },
          options
        );
      }
      if (active && token === generation)
        emit('registered', canceling.value ? 'canceled' : 'prepared');
    } catch (failure) {
      if (!active || token !== generation) return;
      if ([401, 403, 404].includes(failure.response?.status)) denied();
      else if ([409, 422].includes(failure.response?.status)) {
        confirmed.value = false;
        preview.value = null;
        error.value = message(failure.response?.data?.code);
      } else error.value = text('CONTRACT_SIGNATURES.ACTION_ERROR');
    } finally {
      if (active && token === generation) saving.value = false;
    }
  };
  onBeforeUnmount(() => {
    active = false;
    generation += 1;
    controller?.abort();
    preview.value = null;
    key = null;
  });
  return {
    preview,
    confirmed,
    loading,
    saving,
    error,
    canceling,
    busy,
    available,
    canSubmit,
    load,
    submit,
  };
}
