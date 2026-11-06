import { mount, flushPromises, RouterLinkStub } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Component from './AnalystNativeResponsibilitiesDialog.vue';

const mocks = vi.hoisted(() => ({ route: null, getters: null, list: vi.fn() }));
vi.mock('vue-router', async original => ({
  ...(await original()),
  useRoute: () => mocks.route,
}));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcRelationship', () => ({
  default: { analystNativeResponsibilities: mocks.list },
}));
const Dialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const response = (kind = 'project_tasks', total = 11, page = 1) => ({
  data: {
    analyst: { id: 7, name: 'Current analyst' },
    kind,
    payload: total
      ? [
          {
            id: 14,
            title: 'Authorized native work',
            status: 'backlog',
            updated_at: '2026-11-05T10:00:00Z',
            source_route: {
              name: 'jrc_projects_detail',
              params: { accountId: 1, projectId: 3 },
              query: { taskId: 14 },
            },
          },
        ]
      : [],
    meta: { page, per_page: 10, total },
  },
});
const render = () =>
  mount(Component, {
    props: { analystId: 7 },
    global: { stubs: { Dialog, RouterLink: RouterLinkStub } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUserID: 3,
    getCurrentRole: 'administrator',
    getCurrentUser: { accounts: [] },
  });
  mocks.list.mockResolvedValue(response());
});

it('opens the exact native source and paginates without an assignment or membership write', async () => {
  const wrapper = render();
  await flushPromises();
  expect(wrapper.text()).toContain('Authorized native work');
  expect(wrapper.findComponent(RouterLinkStub).props('to')).toEqual(
    response().data.payload[0].source_route
  );
  expect(mocks.list).toHaveBeenCalledWith(
    '1',
    7,
    { kind: 'project_tasks', page: 1 },
    { signal: expect.any(AbortSignal) }
  );
  mocks.list.mockResolvedValueOnce(response('project_tasks', 11, 2));
  await wrapper.get('[data-testid="native-next"]').trigger('click');
  await flushPromises();
  expect(mocks.list).toHaveBeenLastCalledWith(
    '1',
    7,
    { kind: 'project_tasks', page: 2 },
    { signal: expect.any(AbortSignal) }
  );
  expect(wrapper.get('[data-testid="native-next"]').element.disabled).toBe(
    true
  );
  expect(wrapper.find('form').exists()).toBe(false);
  wrapper.unmount();
});

it('resets pagination and private rows when switching native categories', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper.get('[data-testid="native-next"]').trigger('click');
  await flushPromises();
  mocks.list.mockResolvedValueOnce(response('service_tickets', 0));
  await wrapper
    .get('[data-testid="native-kind-service_tickets"]')
    .trigger('click');
  await flushPromises();
  expect(mocks.list).toHaveBeenLastCalledWith(
    '1',
    7,
    { kind: 'service_tickets', page: 1 },
    { signal: expect.any(AbortSignal) }
  );
  expect(wrapper.text()).not.toContain('Authorized native work');
  expect(
    wrapper
      .get('[data-testid="native-kind-service_tickets"]')
      .attributes('aria-pressed')
  ).toBe('true');
  wrapper.unmount();
});

it('clears rows, totals and links when current source permissions are denied and retries only the native read', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.list.mockRejectedValueOnce({
    response: { status: 403, data: { errors: ['Native permission denied'] } },
  });
  await wrapper.get('[data-testid="native-next"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'Native permission denied'
  );
  expect(wrapper.findComponent(RouterLinkStub).exists()).toBe(false);
  expect(wrapper.text()).not.toContain('Authorized native work');
  await wrapper
    .findAll('button')
    .find(row => row.text() === 'RELATIONSHIP.NATIVE_RESPONSIBILITIES.RETRY')
    .trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
  wrapper.unmount();
});

it('aborts and closes on an identity change and ignores a late authorized response from the former identity', async () => {
  let resolveOld;
  mocks.list.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const wrapper = render();
  const request = mocks.list.mock.calls[0][3];
  mocks.getters.getCurrentRole = 'agent';
  await flushPromises();
  expect(request.signal.aborted).toBe(true);
  expect(wrapper.emitted('close')).toHaveLength(1);
  resolveOld(response());
  await flushPromises();
  expect(wrapper.text()).not.toContain('Authorized native work');
  wrapper.unmount();
});

it('recovers once to a remaining valid page when the last page disappears during a native transfer', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.list
    .mockResolvedValueOnce(response('project_tasks', 0, 2))
    .mockResolvedValueOnce(response('project_tasks', 0, 1));
  await wrapper.get('[data-testid="native-next"]').trigger('click');
  await flushPromises();
  expect(mocks.list).toHaveBeenCalledTimes(3);
  expect(mocks.list).toHaveBeenLastCalledWith(
    '1',
    7,
    { kind: 'project_tasks', page: 1 },
    { signal: expect.any(AbortSignal) }
  );
  expect(wrapper.get('[data-testid="native-previous"]').element.disabled).toBe(
    true
  );
  wrapper.unmount();
});
