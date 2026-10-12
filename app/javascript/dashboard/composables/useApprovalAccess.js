import { computed, ref, watch } from 'vue';
import { approvalClient } from 'dashboard/api/approvals';
export const useApprovalAccess = (accountId, userId, enabled) => {
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
        const result = await approvalClient(account).get('context');
        if (
          current === generation &&
          Number(result.data.account_id) === Number(account)
        )
          context.value = result.data;
      } catch {
        if (current === generation) context.value = null;
      }
    },
    { immediate: true }
  );
  return {
    context,
    visible: computed(
      () =>
        context.value?.scopes?.some(scope => scope.capabilities.length) === true
    ),
  };
};
