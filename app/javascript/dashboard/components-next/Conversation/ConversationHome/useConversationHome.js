import { onBeforeUnmount, ref, watch } from 'vue';
import { useQuickActionContext } from 'dashboard/components-next/layout/useQuickActionAccess';
import api from 'dashboard/api/jrcAi';

export function useConversationHome() {
  const { accountId, userId, user, account, crmAllowed } =
    useQuickActionContext();
  const summary = ref({});
  const loading = ref(false);
  const failed = ref(false);
  const generatedAt = ref(null);
  let generation = 0;
  const refresh = async () => {
    generation += 1;
    const current = generation;
    summary.value = {};
    generatedAt.value = null;
    failed.value = false;
    loading.value = !!account.value;
    if (!account.value) return;
    try {
      const { data } = await api.cockpit('today');
      if (current !== generation) return;
      summary.value = data.summary || {};
      generatedAt.value = data.generated_at || null;
    } catch {
      if (current === generation) failed.value = true;
    } finally {
      if (current === generation) loading.value = false;
    }
  };
  watch([accountId, userId, account], refresh, {
    immediate: true,
    flush: 'sync',
  });
  onBeforeUnmount(() => {
    generation += 1;
  });
  return {
    accountId,
    userId,
    user,
    crmAllowed,
    summary,
    generatedAt,
    loading,
    failed,
    refresh,
  };
}
