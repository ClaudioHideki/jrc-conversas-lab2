import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { backofficeContractVersionsAPI as api } from 'dashboard/api/crm/commercialCycle';
import { useBackofficePresentation } from './useBackofficePresentation';

export function useContractVersions(props) {
  const route = useRoute();
  const store = useStore();
  const { text } = useBackofficePresentation();
  const result = ref(null);
  const page = ref(1);
  const reason = ref('');
  const loading = ref(false);
  const saving = ref(false);
  const error = ref('');
  const notice = ref('');
  const stale = ref(false);
  let generation = 0;
  let controller;
  let intent;
  const identity = computed(() =>
    JSON.stringify([
      route.params.accountId,
      props.record.id,
      props.record.contract?.id,
      store.getters.getCurrentUser?.id,
      store.getters.getCurrentRole,
      store.getters.getCurrentUser?.accounts,
    ])
  );
  const accountId = computed(() => route.params.accountId);
  const busy = computed(() => loading.value || saving.value);
  const canEditDraft = computed(
    () =>
      result.value?.writable &&
      result.value?.contract &&
      !['sent', 'signed'].includes(result.value.contract.signature_status) &&
      !stale.value &&
      !busy.value
  );
  const canGenerate = computed(
    () => canEditDraft.value && result.value?.signer_directory_access !== false
  );
  const canSave = computed(
    () => canGenerate.value && reason.value.trim().length > 0
  );
  const pages = computed(() =>
    Math.max(1, Math.ceil((result.value?.meta.total || 0) / 10))
  );
  const deny = () => {
    result.value = null;
    reason.value = '';
    notice.value = '';
    error.value = text('CONTRACT_VERSIONS.DENIED');
  };
  const failureText = failure => {
    if ([401, 403, 404].includes(failure.response?.status)) {
      deny();
      return text('CONTRACT_VERSIONS.DENIED');
    }
    if (failure.response?.data?.code === 'CONTRACT_SOURCE_CHANGED') {
      stale.value = true;
      return text('CONTRACT_VERSIONS.CHANGED');
    }
    return failure.response?.data?.message || text('CONTRACT_VERSIONS.ERROR');
  };
  const load = async () => {
    generation += 1;
    const token = generation;
    controller?.abort();
    controller = new AbortController();
    result.value = null;
    error.value = '';
    notice.value = '';
    loading.value = true;
    saving.value = false;
    try {
      const { data } = await api.list(
        accountId.value,
        props.record.id,
        { page: page.value },
        { signal: controller.signal }
      );
      if (token !== generation) return false;
      result.value = data;
      stale.value = false;
      return true;
    } catch (failure) {
      if (token === generation) error.value = failureText(failure);
      return false;
    } finally {
      if (token === generation) loading.value = false;
    }
  };
  const generate = async () => {
    if (!canSave.value) return false;
    const token = generation;
    const context = identity.value;
    const payload = {
      expected_source_digest: result.value.contract.source_digest,
      change_reason: reason.value.trim(),
    };
    const input = JSON.stringify(payload);
    if (intent?.input !== input) intent = { input, key: crypto.randomUUID() };
    payload.idempotency_key = intent.key;
    saving.value = true;
    error.value = '';
    notice.value = '';
    try {
      const { data } = await api.create(
        accountId.value,
        props.record.id,
        payload,
        { signal: controller.signal }
      );
      if (token !== generation || context !== identity.value) return false;
      if (!data?.id || !data.pdf_sha256)
        throw new Error('Contract generation was not confirmed');
      intent = null;
      reason.value = '';
      if (!(await load())) return false;
      if (context !== identity.value) return false;
      notice.value = text('CONTRACT_VERSIONS.CREATED');
      return true;
    } catch (failure) {
      if (token === generation && context === identity.value)
        error.value = failureText(failure);
      return false;
    } finally {
      if (context === identity.value) saving.value = false;
    }
  };
  const download = async version => {
    if (busy.value) return;
    const context = identity.value;
    const token = generation;
    error.value = '';
    try {
      const { data } = await api.download(
        accountId.value,
        props.record.id,
        version.id,
        { signal: controller.signal }
      );
      if (context !== identity.value || token !== generation) return;
      const url = URL.createObjectURL(data);
      const link = document.createElement('a');
      link.href = url;
      link.download = `contrato-v${version.number}.pdf`;
      link.click();
      URL.revokeObjectURL(url);
    } catch (failure) {
      if (context === identity.value && token === generation)
        error.value = failureText(failure);
    }
  };
  watch(
    identity,
    () => {
      reason.value = '';
      intent = null;
      page.value = 1;
      stale.value = false;
      load();
    },
    { immediate: true }
  );
  onBeforeUnmount(() => {
    generation += 1;
    controller?.abort();
  });
  const changePage = value => {
    page.value = value;
    load();
  };
  return {
    accountId,
    identity,
    result,
    reason,
    loading,
    saving,
    busy,
    error,
    notice,
    canEditDraft,
    canGenerate,
    canSave,
    page,
    pages,
    load,
    generate,
    download,
    changePage,
    deny,
  };
}
