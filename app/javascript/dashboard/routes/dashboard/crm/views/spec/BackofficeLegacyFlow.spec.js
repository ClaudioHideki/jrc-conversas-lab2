import { mount, flushPromises } from '@vue/test-utils';
import BackofficeLayout from '../backoffice/BackofficeLayout.vue';

const mocks = vi.hoisted(() => ({ replace: vi.fn(), route: null }));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
const stubs = {
  RouterLink: true,
  BackofficeOverview: true,
  BackofficeWorklist: true,
  BackofficeRequest360: true,
  BackofficeNewRequest: true,
};

it.each([
  [
    'implement',
    { requestId: '7' },
    'crm_backoffice_request',
    { accountId: '1', requestId: '7' },
    { tab: 'checklist' },
  ],
  [
    'docs',
    { requestId: '8' },
    'crm_backoffice_request',
    { accountId: '1', requestId: '8' },
    { tab: 'documents' },
  ],
  [
    'process',
    { newRequest: '1' },
    'crm_backoffice_new',
    { accountId: '1' },
    undefined,
  ],
])(
  'preserves saved links from %s and opens a dedicated page',
  async (section, query, name, params, expectedQuery) => {
    mocks.route = {
      params: { accountId: '1', section },
      query,
      fullPath: `/legacy/${section}`,
      name: 'crm_backoffice',
    };
    const wrapper = mount(BackofficeLayout, { global: { stubs } });
    await flushPromises();
    expect(mocks.replace).toHaveBeenCalledWith({
      name,
      params,
      ...(expectedQuery ? { query: expectedQuery } : {}),
    });
    expect(wrapper.findAll('main')).toHaveLength(1);
    expect(wrapper.find('aside').exists()).toBe(false);
    wrapper.unmount();
  }
);
