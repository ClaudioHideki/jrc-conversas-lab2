import { ref } from 'vue';
import { accountId, userId } from './state';
export const useQuickActionContext = () => ({
  accountId,
  userId,
  routeAllowed: name =>
    ['ramal_index', 'inbox_view_conversation'].includes(name),
  policy: { isFeatureFlagEnabled: () => true },
});
export const useQuickActionAccess = () => ({
  ...useQuickActionContext(),
  actions: ref([]),
});
