import { computed, inject, onBeforeUnmount, onMounted, provide, reactive, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import ServiceDeskAPI from 'dashboard/api/serviceDesk';
import ServiceDeskOperations from 'dashboard/api/serviceDeskOperations';
import { createOperationalSession, createOperationalState } from '../helpers/operationalSession.js';
import { canonicalId, hasServiceDeskFeature } from '../helpers/access.js';
import { createServiceDeskSession, createSessionState } from '../helpers/session.js';
const KEY = Symbol('jrc-service-desk-session');
export function provideServiceDesk() {
  const route = useRoute();
  const router = useRouter();
  const store = useStore();
  const accountId = computed(() => canonicalId(route.params.accountId));
  const userId = computed(() => canonicalId(store.getters.getCurrentUserID));
  const enabled = computed(() => hasServiceDeskFeature(store, accountId.value));
  const state = reactive(createSessionState());
  const session = createServiceDeskSession(ServiceDeskAPI, state);
  const operations = createOperationalSession(ServiceDeskOperations, session, reactive(createOperationalState()));
  watch([accountId, userId, enabled], ([account, user, flag]) => {
    operations.clear();
    session.start({ accountId: account, userId: user, enabled: flag });
    if (!flag && account && route.name?.startsWith('jrc_service_desk_')) {
      router.replace({ name: 'home', params: { accountId: account } });
    }
  }, { immediate: true, flush: 'sync' });
  watch(() => state.status, status => { if (status !== 'ready') operations.clear(); }, { flush: 'sync' });
  let timer;
  const revalidate = () => { if (document.visibilityState !== 'hidden') session.revalidate(); };
  onMounted(() => {
    window.addEventListener('focus', revalidate);
    document.addEventListener('visibilitychange', revalidate);
    timer = window.setInterval(revalidate, 60000);
  });
  onBeforeUnmount(() => {
    window.clearInterval(timer); window.removeEventListener('focus', revalidate);
    document.removeEventListener('visibilitychange', revalidate);
    operations.clear(); session.dispose();
  });
  const value = { ...session, state, accountId, userId, enabled, operations };
  provide(KEY, value);
  return value;
}
export function useServiceDesk() {
  const value = inject(KEY);
  if (!value)
    throw new Error('Service Desk provider missing');
  return value;
}
