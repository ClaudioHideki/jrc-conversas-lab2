import { mount, flushPromises } from '@vue/test-utils';
import { reactive, ref } from 'vue';
import ServiceDeskLayout from '../ServiceDeskLayout.vue';

const mocks = vi.hoisted(() => ({
  session: null,
  route: null,
  replace: vi.fn(),
}));
vi.mock('../composables/useServiceDesk', () => ({
  provideServiceDesk: () => mocks.session,
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
  RouterView: { template: '<div data-testid="protected-view" />' },
}));
const Button = {
  props: ['label'],
  template: '<button>{{ label }}</button>',
};

it('clears only the denied segment and reauthorizes native context without unlocking protected data', async () => {
  mocks.route = reactive({
    params: { accountId: '1' },
    meta: { serviceDeskScreen: 'tickets' },
    query: { customer_segment_id: '12', page: '3', q: 'Printer' },
  });
  mocks.replace.mockImplementation(async ({ query }) => {
    mocks.route.query = query;
  });
  const retry = vi.fn();
  mocks.session = {
    state: reactive({ status: 'denied', context: null, resources: {} }),
    enabled: ref(true),
    accountId: ref('1'),
    userId: ref('2'),
    operations: { state: reactive({ notice: null }) },
    retry,
  };
  const wrapper = mount(ServiceDeskLayout, {
    global: {
      stubs: {
        Button,
        ModuleTabs: true,
        Breadcrumb: true,
        ServiceDeskState: true,
        ScreenGuidance: true,
        WriteFeedback: true,
      },
    },
  });
  expect(wrapper.find('[data-testid="protected-view"]').exists()).toBe(false);
  await wrapper.get('button').trigger('click');
  await flushPromises();
  expect(mocks.replace).toHaveBeenCalledWith({ query: { q: 'Printer' } });
  expect(retry).toHaveBeenCalledTimes(1);
  expect(mocks.session.state.status).toBe('denied');
  expect(wrapper.find('[data-testid="protected-view"]').exists()).toBe(false);
  wrapper.unmount();
});
