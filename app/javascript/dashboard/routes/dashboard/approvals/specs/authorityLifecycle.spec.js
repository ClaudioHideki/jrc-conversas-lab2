import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { createI18n } from 'vue-i18n';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import ApprovalsPage from '../ApprovalsPage.vue';
import RequestDetail from '../RequestDetail.vue';
import locale from 'dashboard/i18n/locale/en/jrcApprovals.json';
import { approvalClient } from 'dashboard/api/approvals';

const navigation = vi.hoisted(() => ({ route: null, push: vi.fn() }));
vi.mock('vue-router', () => ({
  useRoute: () => navigation.route,
  useRouter: () => ({ push: navigation.push }),
}));
vi.mock('dashboard/api/approvals', () => ({ approvalClient: vi.fn() }));
const Button = {
  props: ['label', 'disabled'],
  template: '<button :disabled="disabled">{{ label }}</button>',
};
let wrapper;
let member;
let store;
let api;
const context = () => ({
  account_id: 1,
  member_id: member.actor,
  scopes: [
    { issuer_company_id: 10, business_unit_id: 20, capabilities: ['decide'] },
  ],
});
const source = (id = 501, name = 'Synthetic private approval') => ({
  id,
  resource_type: 'JrcCrm::Proposal',
  resource_id: id + 100,
  state: 'pending',
  lock_version: 4,
  policy_name: name,
  issuer_company_id: 10,
  business_unit_id: 20,
  stages: [{ code: 'review', quorum: 1, approved_count: 0 }],
  allowed_decisions: [
    {
      step_code: 'review',
      choices: [{ delegation_id: null, actions: ['approved'] }],
    },
  ],
});
const nativeResponse = (
  path,
  record = source(Number(navigation.route.params.id))
) => {
  let data = record;
  if (path === 'context') data = context();
  if (path === 'requests') data = [record];
  if (path === 'requests/summary')
    data = { pending: 1, approved: 0, rejected: 0, due_today: 0 };
  return {
    data,
    headers: { 'x-total-count': '1', 'x-page': '1', 'x-per-page': '25' },
  };
};
const decision = () => ({
  expected_version: 4,
  step_code: 'review',
  decision: 'approved',
  delegation_id: null,
  reason: 'Synthetic explicit review',
});
beforeEach(() => {
  vi.resetAllMocks();
  member = reactive({ actor: 7, role: 'agent', grant: 1, presence: 'online' });
  navigation.route = reactive({
    params: { accountId: '1', screen: 'inbox', id: '501' },
    query: {},
    fullPath: '/app/accounts/1/approvals/inbox/501',
  });
  store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUserID: () => member.actor,
      getCurrentRole: () => member.role,
      getCurrentUser: () => ({
        id: member.actor,
        accounts: [
          {
            id: 1,
            role: member.role,
            custom_role_id: member.grant,
            availability: member.presence,
          },
        ],
      }),
    },
  });
  api = {
    get: vi
      .fn()
      .mockImplementation(path => Promise.resolve(nativeResponse(path))),
    post: vi.fn().mockResolvedValue({ data: source() }),
  };
  approvalClient.mockReturnValue(api);
});
afterEach(() => wrapper?.unmount());
const render = async () => {
  wrapper = mount(ApprovalsPage, {
    global: {
      plugins: [
        store,
        createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
      ],
      stubs: { Button, RouterLink: true },
    },
  });
  await flushPromises();
};

it.each([500, 422, undefined])(
  'clears previous filter counts when the next summary fails (%s)',
  async status => {
    await render();
    expect(wrapper.get('[data-metric="pending"]').text()).toBe('1');
    api.get.mockImplementation(path =>
      path === 'requests/summary'
        ? Promise.reject(
            status
              ? { response: { status, data: {} } }
              : Error('Synthetic network failure')
          )
        : Promise.resolve(nativeResponse(path))
    );
    navigation.route.query = { q: 'different authorized filter' };
    navigation.route.fullPath += '?q=different';
    await flushPromises();
    expect(wrapper.get('[data-metric="pending"]').text()).toBe('—');
  }
);

it('clears a protected request and rereads native capabilities after a same-account grant change', async () => {
  await render();
  api.get.mockImplementation(path =>
    Promise.resolve({
      data: path === 'context' ? { ...context(), scopes: [] } : source(),
    })
  );
  member.grant = 2;
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic private approval');
  expect(
    api.get.mock.calls.filter(([path]) => path === 'context')
  ).toHaveLength(2);
  expect(wrapper.findComponent(RequestDetail).exists()).toBe(false);
});

it('ignores an old actor request read after a replacement actor loads the same route', async () => {
  let finish;
  api.get.mockImplementation(path =>
    path === 'context' || path === 'requests' || path === 'requests/summary'
      ? Promise.resolve(nativeResponse(path))
      : new Promise(resolve => {
          finish = resolve;
        })
  );
  await render();
  api.get.mockImplementation(path =>
    Promise.resolve(nativeResponse(path, source(501, 'Current actor approval')))
  );
  member.actor = 99;
  await flushPromises();
  finish({ data: source(501, 'Old private approval') });
  await flushPromises();
  expect(wrapper.text()).toContain('Current actor approval');
  expect(wrapper.text()).not.toContain('Old private approval');
});

it('does not reload or acknowledge an obsolete decision after native access changes', async () => {
  let finish;
  api.post.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  wrapper.findComponent(RequestDetail).vm.$emit('decide', decision());
  member.grant = 2;
  await flushPromises();
  const reads = api.get.mock.calls.length;
  finish({ data: source() });
  await flushPromises();
  expect(api.get).toHaveBeenCalledTimes(reads);
  expect(wrapper.findAll('[role="status"]')).toHaveLength(0);
});

it('does not follow a pending decision into a different request route', async () => {
  let finish;
  api.post.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  wrapper.findComponent(RequestDetail).vm.$emit('decide', decision());
  navigation.route.params.id = '502';
  navigation.route.fullPath = '/app/accounts/1/approvals/inbox/502';
  await flushPromises();
  const reads = api.get.mock.calls.length;
  finish({ data: source() });
  await flushPromises();
  expect(wrapper.findComponent(RequestDetail).props('request').id).toBe(502);
  expect(api.get).toHaveBeenCalledTimes(reads);
  expect(wrapper.findAll('[role="status"]')).toHaveLength(0);
});

it('does not perform another native read after unmounting a pending decision', async () => {
  let finish;
  api.post.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  wrapper.findComponent(RequestDetail).vm.$emit('decide', decision());
  wrapper.unmount();
  const reads = api.get.mock.calls.length;
  finish({ data: source() });
  await flushPromises();
  expect(api.get).toHaveBeenCalledTimes(reads);
});

it('preserves a review reason and context through native presence-only updates', async () => {
  await render();
  await wrapper.get('textarea').setValue('Current review reason');
  member.presence = 'offline';
  await flushPromises();
  expect(wrapper.get('textarea').element.value).toBe('Current review reason');
  expect(api.get.mock.calls.map(([path]) => path)).toEqual([
    'context',
    'requests',
    'requests/501',
    'requests/summary',
  ]);
});

it('retries the initial native context through Refresh after a network failure', async () => {
  api.get.mockRejectedValueOnce(new Error('synthetic local transport failure'));
  await render();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  await wrapper
    .findAll('button')
    .find(button => button.text() === 'Refresh')
    .trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(RequestDetail).exists()).toBe(true);
  expect(
    api.get.mock.calls.filter(([path]) => path === 'context')
  ).toHaveLength(2);
});

it('sends the original native version, explicit decision and reason once while a decision is pending', async () => {
  let finish;
  api.post.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  wrapper.findComponent(RequestDetail).vm.$emit('decide', decision());
  wrapper.findComponent(RequestDetail).vm.$emit('decide', decision());
  expect(api.post).toHaveBeenCalledTimes(1);
  expect(api.post).toHaveBeenCalledWith('requests/501/decide', {
    decision: expect.objectContaining(decision()),
  });
  finish({ data: source() });
  await flushPromises();
});
