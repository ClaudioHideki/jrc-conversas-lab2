import { mount } from '@vue/test-utils';
import { reactive } from 'vue';
import { useEventBus } from '@vueuse/core';
import {
  quickActionTarget,
  useQuickActionTarget,
} from '../useQuickActionTarget';
const state = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => state.route }));

describe('existing CRM form shortcut targets', () => {
  let wrapper;
  beforeEach(() => {
    state.route = reactive({ name: 'crm_leads', params: { accountId: '1' } });
  });
  afterEach(() => wrapper?.unmount());
  it.each(['crm_leads', 'crm_deals', 'crm_activities'])(
    'reuses %s only in its current account and removes the listener on unmount',
    name => {
      state.route.name = name;
      const open = vi.fn();
      wrapper = mount({
        setup() {
          useQuickActionTarget(name, open);
        },
        template: '<div />',
      });
      const bus = useEventBus(quickActionTarget);
      bus.emit({ name, accountId: 2 });
      bus.emit({ name: 'crm_other', accountId: 1 });
      expect(open).not.toHaveBeenCalled();
      bus.emit({ name, accountId: 1 });
      bus.emit({ name, accountId: 1 });
      expect(open).toHaveBeenCalledTimes(2);
      state.route.params.accountId = '2';
      bus.emit({ name, accountId: 1 });
      expect(open).toHaveBeenCalledTimes(2);
      bus.emit({ name, accountId: 2 });
      expect(open).toHaveBeenCalledTimes(3);
      state.route.name = 'crm_other';
      bus.emit({ name, accountId: 2 });
      expect(open).toHaveBeenCalledTimes(3);
      state.route.name = name;
      wrapper.unmount();
      wrapper = null;
      bus.emit({ name, accountId: 2 });
      expect(open).toHaveBeenCalledTimes(3);
    }
  );
});
