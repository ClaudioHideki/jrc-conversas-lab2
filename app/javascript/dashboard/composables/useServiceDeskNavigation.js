import { reactive, watch, onMounted, onBeforeUnmount } from 'vue';
import ServiceDeskAPI from 'dashboard/api/serviceDesk';
import { createNavigationAccess } from 'dashboard/routes/dashboard/serviceDesk/helpers/nativeIntegration';

// Only an affirmative backend context reveals the additional sidebar entry.
// No network call while the feature is off; no persistent or cross-account cache.
export function useServiceDeskNavigation(accountId, userId, enabled) {
  const state = reactive({ visible: false, route: null, context: null, status: 'idle' });
  const access = createNavigationAccess(ServiceDeskAPI, state);
  const refresh = () => access.refresh({ accountId: accountId.value, userId: userId.value, enabled: enabled.value });
  const activeRefresh = () => { if (document.visibilityState !== 'hidden') refresh(); };
  watch([accountId, userId, enabled], refresh, { immediate: true, flush: 'sync' });
  let timer;
  onMounted(() => {
    window.addEventListener('focus', activeRefresh);
    document.addEventListener('visibilitychange', activeRefresh);
    timer = window.setInterval(activeRefresh, 60000);
  });
  onBeforeUnmount(() => {
    access.dispose(); window.clearInterval(timer);
    window.removeEventListener('focus', activeRefresh);
    document.removeEventListener('visibilitychange', activeRefresh);
  });
  return state;
}
