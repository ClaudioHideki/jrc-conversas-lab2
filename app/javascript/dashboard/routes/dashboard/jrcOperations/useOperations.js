import { reactive, computed, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { request, errorMessage } from './api';
const states = reactive({});
export function useOperations() {
  const route = useRoute();
  const store = useStore();
  const accountId = computed(() => String(route.params.accountId || ''));
  const userId = computed(() => store.getters.getCurrentUserID);
  const key = computed(() => `${accountId.value}:${userId.value}`);
  const state = computed(() => {
    if (!states[key.value])
      states[key.value] = {
        data: null,
        loading: false,
        error: '',
        loadedAt: 0,
      };
    return states[key.value];
  });
  async function refresh(force = false) {
    if (!accountId.value) return;
    const target = state.value;
    if (target.loading || (!force && target.loadedAt > Date.now() - 30000))
      return;
    target.loading = true;
    target.error = '';
    try {
      target.data = (await request(accountId.value, 'operations/status')).data;
      target.loadedAt = Date.now();
    } catch (error) {
      target.error = errorMessage(error);
      target.data = null;
    } finally {
      target.loading = false;
    }
  }
  watch(key, () => refresh(), { immediate: true });
  return {
    accountId,
    userId,
    status: computed(() => state.value.data),
    loading: computed(() => state.value.loading),
    error: computed(() => state.value.error),
    refresh,
  };
}
