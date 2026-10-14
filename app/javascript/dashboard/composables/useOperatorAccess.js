import { computed, ref, watch } from 'vue';
import { operatorClient } from 'dashboard/api/jrcOperator';
export const useOperatorAccess = (accountId, userId, enabled) => {
  const context = ref(null);
  let generation = 0;
  watch(
    [accountId, userId, enabled],
    async ([account, user, active]) => {
      generation += 1;
      const current = generation;
      context.value = null;
      if (!account || !user || !active) return;
      try {
        const result = await operatorClient(account).context();
        if (current === generation) context.value = result;
      } catch {
        if (current === generation) context.value = null;
      }
    },
    { immediate: true }
  );
  return { visible: computed(() => context.value?.enabled === true) };
};
