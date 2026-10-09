import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import KnowledgeView from '../KnowledgeView.vue';

const mocks = vi.hoisted(() => ({ session: null, route: null, get: vi.fn() }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('../../composables/useServiceDesk', () => ({
  useServiceDesk: () => mocks.session,
}));
const payload = (account = '1', title = 'Restoration guide') => ({
  data: {
    contract_version: 1,
    account_id: account,
    items: [
      {
        id: '17',
        title,
        description: 'Published guidance',
        locale: 'en',
        path: '/hc/test/articles/guide',
        visibility: 'published_public',
        source: 'native_help_center',
      },
    ],
    meta: { total: 1 },
  },
});

beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ query: {} });
  mocks.session = reactive({
    state: { status: 'ready' },
    accountId: { value: '1' },
    userId: { value: '7' },
  });
  mocks.get.mockResolvedValue(payload());
  vi.stubGlobal('axios', { get: mocks.get });
});

describe('Native knowledge in Service Desk', () => {
  it('uses the ticket context on arrival and when navigating to another ticket', async () => {
    mocks.route.query.query = 'Printer error';
    const wrapper = mount(KnowledgeView);
    await flushPromises();
    expect(mocks.get.mock.calls.at(-1)[1].params.query).toBe('Printer error');
    mocks.route.query.query = 'Network error';
    await flushPromises();
    expect(mocks.get.mock.calls.at(-1)[1].params).toEqual({
      query: 'Network error',
      page: 1,
    });
    wrapper.unmount();
  });

  it('opens the existing published article rather than creating another knowledge record', async () => {
    const wrapper = mount(KnowledgeView);
    await flushPromises();
    expect(wrapper.text()).toContain('Restoration guide');
    expect(wrapper.find('a').attributes('href')).toBe(
      '/hc/test/articles/guide'
    );
    expect(wrapper.find('a').attributes('rel')).toContain('noopener');
    wrapper.unmount();
  });

  it('rejects an account-mismatched response', async () => {
    mocks.get.mockResolvedValue(payload('2', 'Foreign guidance'));
    const wrapper = mount(KnowledgeView);
    await flushPromises();
    expect(wrapper.text()).not.toContain('Foreign guidance');
    expect(wrapper.find('a').exists()).toBe(false);
    wrapper.unmount();
  });

  it('rejects a non-published source instead of exposing a draft', async () => {
    const result = payload('1', 'Internal draft');
    result.data.items[0].visibility = 'internal';
    mocks.get.mockResolvedValue(result);
    const wrapper = mount(KnowledgeView);
    await flushPromises();
    expect(wrapper.text()).not.toContain('Internal draft');
    wrapper.unmount();
  });

  it('discards a delayed result after switching accounts', async () => {
    let resolveOld;
    mocks.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mount(KnowledgeView);
    mocks.get.mockResolvedValue(payload('2', 'Current company guide'));
    mocks.session.accountId.value = '2';
    await flushPromises();
    resolveOld(payload('1', 'Previous company guide'));
    await flushPromises();
    expect(wrapper.text()).toContain('Current company guide');
    expect(wrapper.text()).not.toContain('Previous company guide');
    wrapper.unmount();
  });

  it('clears published content immediately when operator access is revoked', async () => {
    const wrapper = mount(KnowledgeView);
    await flushPromises();
    mocks.session.state.status = 'denied';
    await flushPromises();
    expect(wrapper.text()).not.toContain('Restoration guide');
    expect(wrapper.find('a').exists()).toBe(false);
    wrapper.unmount();
  });
});
