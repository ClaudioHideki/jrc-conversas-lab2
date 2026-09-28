import { reactive, watch, onMounted, onBeforeUnmount } from 'vue';
import API from 'dashboard/api/serviceDeskStructure';
import { createStructureAccess } from 'dashboard/routes/dashboard/serviceDesk/helpers/structure';
// Independent structural context. Never passed into the operational Service Desk provider.
export function useServiceDeskStructure(accountId, userId, enabled) {
  const state = reactive({ visible: false, context: null, status: 'idle' });
  const access = createStructureAccess(API, state);
  const refresh = () => access.refresh({ accountId: accountId.value, userId: userId.value, enabled: enabled.value });
  const activeRefresh = () => { if (document.visibilityState !== 'hidden') refresh(); };
  watch([accountId, userId, enabled], refresh, { immediate: true, flush: 'sync' });
  let timer;
  onMounted(() => {
    window.addEventListener('focus', activeRefresh); document.addEventListener('visibilitychange', activeRefresh);
    timer = window.setInterval(activeRefresh, 60000);
  });
  onBeforeUnmount(() => {
    access.dispose(); window.clearInterval(timer);
    window.removeEventListener('focus', activeRefresh); document.removeEventListener('visibilitychange', activeRefresh);
  });
  return { state, refresh };
}
