import { reactive, watch, onMounted, onBeforeUnmount } from 'vue';
import API from 'dashboard/api/serviceDeskStructure';
import { createStructureAccess } from 'dashboard/routes/dashboard/serviceDesk/helpers/structure';
import { canonicalId } from 'dashboard/routes/dashboard/serviceDesk/helpers/access';
// Independent structural context. Never passed into the operational Service Desk provider.
export function useServiceDeskStructure(accountId, userId, enabled) {
  const state = reactive({ visible: false, context: null, status: 'idle' });
  const access = createStructureAccess(API, state);
  let pending;
  const refresh = () => {
    const identity = {
      accountId: canonicalId(accountId.value),
      userId: canonicalId(userId.value),
      enabled: enabled.value,
    };
    if (
      pending?.enabled === true &&
      identity.enabled === true &&
      identity.accountId &&
      identity.userId &&
      pending.accountId === identity.accountId &&
      pending.userId === identity.userId
    )
      return pending.promise;
    const request = { ...identity };
    pending = request;
    request.promise = access.refresh(identity).finally(() => {
      if (pending === request) pending = null;
    });
    return request.promise;
  };
  const activeRefresh = () => { if (document.visibilityState !== 'hidden') refresh(); };
  watch([accountId, userId, enabled], refresh, { immediate: true, flush: 'sync' });
  let timer;
  onMounted(() => {
    window.addEventListener('focus', activeRefresh); document.addEventListener('visibilitychange', activeRefresh);
    timer = window.setInterval(activeRefresh, 60000);
  });
  onBeforeUnmount(() => {
    pending = null;
    access.dispose(); window.clearInterval(timer);
    window.removeEventListener('focus', activeRefresh); document.removeEventListener('visibilitychange', activeRefresh);
  });
  return { state, refresh };
}
