import { useEventBus } from '@vueuse/core';
import { onBeforeUnmount } from 'vue';
import { useRoute } from 'vue-router';

// Local presentation event, scoped to the mounted page and its active Account.
export const quickActionTarget = Symbol('jrc-quick-action-target');
export const quickActionCommand = Symbol('jrc-quick-action-command');

export function useQuickActionTarget(name, activate) {
  const route = useRoute();
  const stop = useEventBus(quickActionTarget).on(request => {
    if (
      request.name === name &&
      route.name === name &&
      Number(route.params.accountId) === request.accountId
    )
      activate();
  });
  onBeforeUnmount(stop);
}
