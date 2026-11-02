import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import api from 'dashboard/api/crm/backofficeSignatures';
import { useBackofficePresentation } from './useBackofficePresentation';

export function useSignatureHistory(props) {
  const route = useRoute();
  const router = useRouter();
  const store = useStore();
  const { text } = useBackofficePresentation();
  const result = ref(null);
  const selection = ref(null);
  const loading = ref(false);
  const error = ref('');
  let generation = 0;
  let controller;
  const accountId = computed(() => route.params.accountId);
  const identity = computed(() =>
    JSON.stringify([
      accountId.value,
      props.record.id,
      props.record.contract?.id,
      store.getters.getCurrentUser,
      store.getters.getCurrentRole,
    ])
  );
  const page = computed(() =>
    Math.min(10000, Math.max(1, Number(route.query.signaturePage) || 1))
  );
  const deny = () => {
    generation += 1;
    controller?.abort();
    result.value = null;
    selection.value = null;
    loading.value = false;
    error.value = text('CONTRACT_SIGNATURES.DENIED');
  };
  const load = async () => {
    generation += 1;
    const token = generation;
    controller?.abort();
    controller = new AbortController();
    result.value = null;
    selection.value = null;
    error.value = '';
    loading.value = true;
    try {
      const { data } = await api.list(
        accountId.value,
        props.record.id,
        page.value,
        { signal: controller.signal }
      );
      if (token === generation) result.value = data;
    } catch (failure) {
      if (token !== generation) return;
      if ([401, 403, 404].includes(failure.response?.status)) deny();
      else error.value = text('CONTRACT_SIGNATURES.ERROR');
    } finally {
      if (token === generation) loading.value = false;
    }
  };
  const changePage = value =>
    router.replace({
      query: {
        ...route.query,
        tab: 'contracts',
        contractTab: 'signature',
        signaturePage: String(value),
      },
    });
  watch([identity, page], load, { immediate: true });
  onBeforeUnmount(() => {
    generation += 1;
    controller?.abort();
    result.value = null;
    selection.value = null;
  });
  return {
    accountId,
    identity,
    result,
    selection,
    loading,
    error,
    load,
    changePage,
    deny,
  };
}
