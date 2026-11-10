import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import AgendaRecord from '../AgendaRecord.vue';
import { activitiesAPI, followUpsAPI } from 'dashboard/api/crm';

const navigation = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => navigation.route }));
vi.mock('dashboard/api/crm', () => ({
  activitiesAPI: { show: vi.fn(), complete: vi.fn() },
  followUpsAPI: { show: vi.fn(), complete: vi.fn() },
}));
const record = title => ({ data: { id: 9, title, status: 'scheduled' } });
let wrapper;
let member;
let store;
beforeEach(() => {
  vi.resetAllMocks();
  member = reactive({ actor: 3, role: 'agent', presence: 'online' });
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { activityId: '9' },
  });
  store = createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUserID: () => member.actor,
      getCurrentRole: () => member.role,
      getCurrentUser: () => ({
        id: member.actor,
        accounts: [{ id: 1, role: member.role, availability: member.presence }],
      }),
    },
  });
  activitiesAPI.show.mockResolvedValue(record('Synthetic private appointment'));
  activitiesAPI.complete.mockResolvedValue({
    data: { id: 9, status: 'completed' },
  });
  followUpsAPI.show.mockResolvedValue(record('Synthetic follow-up'));
  followUpsAPI.complete.mockResolvedValue({
    data: { id: 9, is_completed: true },
  });
});
afterEach(() => wrapper?.unmount());
const render = async () => {
  wrapper = mount(AgendaRecord, { global: { plugins: [store] } });
  await flushPromises();
};

it('clears private content and rereads native authorization after an effective role change', async () => {
  await render();
  activitiesAPI.show.mockRejectedValueOnce({ response: { status: 403 } });
  member.role = 'administrator';
  await flushPromises();
  expect(wrapper.text()).not.toContain('Synthetic private appointment');
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(activitiesAPI.show).toHaveBeenCalledTimes(2);
});

it('does not restore a previous actor private read after the new actor has loaded the same URL', async () => {
  let finish;
  activitiesAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  activitiesAPI.show.mockResolvedValueOnce(record('Current authorized actor'));
  member.actor = 99;
  await flushPromises();
  finish(record('Obsolete private content'));
  await flushPromises();
  expect(wrapper.text()).toContain('Current authorized actor');
  expect(wrapper.text()).not.toContain('Obsolete private content');
});

it('prevents a same-tick detached edit action after effective access changes', async () => {
  await render();
  const button = wrapper.get('[data-testid="agenda-record-edit"]');
  member.role = 'administrator';
  await button.trigger('click');
  expect(wrapper.emitted('edit')).toBeUndefined();
});

it('ignores an activity completion receipt after switching to a distinct native follow-up with the same ID', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('[data-testid="agenda-record-complete"]').trigger('click');
  navigation.route.query = { followUpId: '9' };
  await flushPromises();
  finish({
    data: {
      id: 9,
      title: 'Obsolete completed appointment',
      status: 'completed',
    },
  });
  await flushPromises();
  expect(wrapper.text()).toContain('Synthetic follow-up');
  expect(wrapper.text()).not.toContain('Obsolete completed appointment');
  expect(wrapper.emitted('changed')).toBeUndefined();
});

it('does not emit a mutation receipt after the linked panel is unmounted', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('[data-testid="agenda-record-complete"]').trigger('click');
  wrapper.unmount();
  finish({ data: { id: 9, status: 'completed' } });
  await flushPromises();
  expect(wrapper.emitted('changed')).toBeUndefined();
});

it('preserves current content and pending work when only native presence changes', async () => {
  await render();
  member.presence = 'offline';
  await flushPromises();
  expect(wrapper.text()).toContain('Synthetic private appointment');
  expect(activitiesAPI.show).toHaveBeenCalledTimes(1);
});

it('does not allow a second completion during a refresh of the same pending native source', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('[data-testid="agenda-record-complete"]').trigger('click');
  await wrapper.setProps({ refreshKey: 1 });
  await flushPromises();
  expect(
    wrapper.get('[data-testid="agenda-record-complete"]').element.disabled
  ).toBe(true);
  finish({ data: { id: 9, status: 'completed' } });
  await flushPromises();
});

it('does not overwrite an acknowledged native completion with an older in-flight refresh', async () => {
  let finishWrite;
  let finishRead;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finishWrite = resolve;
      })
  );
  await render();
  await wrapper.get('[data-testid="agenda-record-complete"]').trigger('click');
  activitiesAPI.show.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finishRead = resolve;
      })
  );
  await wrapper.setProps({ refreshKey: 1 });
  finishWrite({
    data: { id: 9, title: 'Persisted completion', status: 'completed' },
  });
  await flushPromises();
  finishRead(record('Old scheduled snapshot'));
  await flushPromises();
  expect(wrapper.text()).toContain('Persisted completion');
  expect(wrapper.text()).not.toContain('Old scheduled snapshot');
  expect(wrapper.find('[data-testid="agenda-record-complete"]').exists()).toBe(
    false
  );
  expect(wrapper.emitted('changed')).toHaveLength(1);
});

it('does not notify a replacement actor about a prior authority completion', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('[data-testid="agenda-record-complete"]').trigger('click');
  activitiesAPI.show.mockResolvedValueOnce(
    record('New actor authorized appointment')
  );
  member.actor = 99;
  await flushPromises();
  finish({
    data: { id: 9, title: 'Prior actor receipt', status: 'completed' },
  });
  await flushPromises();
  expect(wrapper.text()).toContain('New actor authorized appointment');
  expect(wrapper.text()).not.toContain('Prior actor receipt');
  expect(wrapper.emitted('changed')).toBeUndefined();
});
