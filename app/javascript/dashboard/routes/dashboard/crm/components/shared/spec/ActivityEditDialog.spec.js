import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { beforeEach, expect, it, vi } from 'vitest';
import Component from '../ActivityEditDialog.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  getters: null,
  show: vi.fn(),
  update: vi.fn(),
}));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/crm', () => ({
  activitiesAPI: { showInAccount: mocks.show, updateInAccount: mocks.update },
}));
const Dialog = {
  props: ['disableConfirmButton', 'isLoading'],
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const source = () => ({
  data: {
    id: 9,
    title: 'Current native commitment',
    description: 'Current private draft',
    status: 'scheduled',
    due_at_local: '2026-11-06T11:30:12',
    time_zone: 'America/Sao_Paulo',
    edit_version: '2026-11-06T10:00:00.123456Z',
  },
});
const render = () =>
  mount(Component, { props: { activityId: 9 }, global: { stubs: { Dialog } } });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' } });
  mocks.getters = reactive({
    getCurrentUserID: 3,
    getCurrentRole: 'administrator',
    getCurrentUser: { accounts: [] },
  });
  mocks.show.mockResolvedValue(source());
  mocks.update.mockResolvedValue(source());
});

it('loads the original source and saves only editable content with its exact version and captured account', async () => {
  const wrapper = render();
  await flushPromises();
  expect(mocks.show).toHaveBeenCalledWith('1', 9, {
    signal: expect.any(AbortSignal),
  });
  expect(
    wrapper.get('[data-testid="activity-due"]').element.valueAsNumber
  ).toBe(Date.parse('2026-11-06T11:30:12Z'));
  await wrapper
    .get('[data-testid="activity-title"]')
    .setValue('Revised commitment');
  await wrapper
    .get('[data-testid="activity-due"]')
    .setValue('2026-11-07T10:15:12');
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  await flushPromises();
  expect(mocks.update).toHaveBeenCalledWith(
    '1',
    9,
    {
      expected_version: source().data.edit_version,
      activity: {
        title: 'Revised commitment',
        description: 'Current private draft',
        due_at: wrapper.get('[data-testid="activity-due"]').element.value,
      },
    },
    { signal: expect.any(AbortSignal) }
  );
  expect(wrapper.emitted('saved')).toHaveLength(1);
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});

it('retains a rejected draft and permits one explicit retry without creating another activity', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .get('[data-testid="activity-title"]')
    .setValue('Retained draft');
  mocks.update.mockRejectedValueOnce({ response: { status: 422 } });
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  await flushPromises();
  expect(wrapper.get('[data-testid="activity-title"]').element.value).toBe(
    'Retained draft'
  );
  expect(wrapper.get('[role="alert"]').text()).toContain(
    'CRM.ACTIVITY_EDIT.FAILED'
  );
  expect(wrapper.emitted('saved')).toBeUndefined();
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  await flushPromises();
  expect(mocks.update).toHaveBeenCalledTimes(2);
  expect(wrapper.emitted('saved')).toHaveLength(1);
  wrapper.unmount();
});

it('preserves a conflicting draft, prevents blind retries and reloads only on explicit discard', async () => {
  const wrapper = render();
  await flushPromises();
  await wrapper
    .get('[data-testid="activity-title"]')
    .setValue('Conflicting draft');
  mocks.update.mockRejectedValueOnce({ response: { status: 409 } });
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  await flushPromises();
  expect(wrapper.get('[data-testid="activity-title"]').element.value).toBe(
    'Conflicting draft'
  );
  expect(wrapper.findComponent(Dialog).props('disableConfirmButton')).toBe(
    true
  );
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  await flushPromises();
  expect(mocks.update).toHaveBeenCalledTimes(1);
  await wrapper.get('[data-testid="activity-reload"]').trigger('click');
  await flushPromises();
  expect(wrapper.get('[data-testid="activity-title"]').element.value).toBe(
    'Current native commitment'
  );
  expect(wrapper.findComponent(Dialog).props('disableConfirmButton')).toBe(
    false
  );
  wrapper.unmount();
});

it('clears private content when native update access is denied', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.update.mockRejectedValueOnce({ response: { status: 403 } });
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  await flushPromises();
  expect(wrapper.find('[data-testid="activity-description"]').exists()).toBe(
    false
  );
  expect(wrapper.text()).not.toContain('Current private draft');
  expect(wrapper.emitted('saved')).toBeUndefined();
  wrapper.unmount();
});

it('aborts and closes on account changes, ignoring a late private read and preventing a write to another account', async () => {
  let resolveOld;
  mocks.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        resolveOld = resolve;
      })
  );
  const wrapper = render();
  const request = mocks.show.mock.calls[0][2];
  mocks.route.params.accountId = '2';
  await flushPromises();
  expect(request.signal.aborted).toBe(true);
  expect(wrapper.emitted('close')).toHaveLength(1);
  resolveOld(source());
  await flushPromises();
  expect(wrapper.find('[data-testid="activity-title"]').exists()).toBe(false);
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  expect(mocks.update).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('does not edit completed records and retries an unavailable read without disclosing an old source', async () => {
  mocks.show.mockRejectedValueOnce(new Error('denied'));
  const wrapper = render();
  await flushPromises();
  expect(wrapper.find('[data-testid="activity-title"]').exists()).toBe(false);
  const closed = source();
  closed.data.status = 'completed';
  mocks.show.mockResolvedValueOnce(closed);
  await wrapper.get('[data-testid="activity-reload"]').trigger('click');
  await flushPromises();
  expect(wrapper.findComponent(Dialog).props('disableConfirmButton')).toBe(
    true
  );
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  expect(mocks.update).not.toHaveBeenCalled();
  wrapper.unmount();
});

it('blocks duplicate submissions while the native update is pending', async () => {
  let complete;
  mocks.update.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        complete = resolve;
      })
  );
  const wrapper = render();
  await flushPromises();
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  expect(mocks.update).toHaveBeenCalledTimes(1);
  complete(source());
  await flushPromises();
  expect(wrapper.emitted('saved')).toHaveLength(1);
  wrapper.unmount();
});

it('rejects a same-tick identity change before the close watcher has run', async () => {
  const wrapper = render();
  await flushPromises();
  mocks.route.params.accountId = '2';
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  expect(mocks.update).not.toHaveBeenCalled();
  await flushPromises();
  expect(wrapper.emitted('close')).toHaveLength(1);
  wrapper.unmount();
});
