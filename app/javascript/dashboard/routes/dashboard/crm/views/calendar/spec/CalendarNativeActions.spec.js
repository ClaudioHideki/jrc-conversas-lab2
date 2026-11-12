import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import { createStore } from 'vuex';
import { beforeEach, afterEach, it, expect, vi } from 'vitest';
import CalendarView from '../CalendarView.vue';
import ActivityEditDialog from '../../../components/shared/ActivityEditDialog.vue';
import activities from 'dashboard/store/crm/modules/activities';
import { activitiesAPI } from 'dashboard/api/crm';

const navigation = vi.hoisted(() => ({ route: null }));
vi.mock('vue-router', () => ({ useRoute: () => navigation.route }));
vi.mock('dashboard/api/crm', () => ({
  activitiesAPI: {
    list: vi.fn(),
    complete: vi.fn(),
    showInAccount: vi.fn(),
    updateInAccount: vi.fn(),
  },
}));
const Dialog = {
  props: ['disableConfirmButton', 'isLoading'],
  setup(_, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section data-testid="native-edit-dialog"><slot /></section>',
};
const source = () => ({
  id: 1,
  title: 'Synthetic calendar source',
  description: 'Synthetic private appointment',
  activity_type: 'meeting',
  status: 'scheduled',
  due_at: '2026-11-07T12:00:00Z',
  due_at_local: '2026-11-07T09:00:00',
  edit_version: '2026-11-07T10:00:00.123456Z',
  time_zone: 'America/Sao_Paulo',
});
let wrapper;
let authority;
let store;
beforeEach(() => {
  vi.resetAllMocks();
  authority = reactive({
    account: 1,
    actor: 7,
    role: 'agent',
    presence: 'online',
  });
  navigation.route = reactive({
    params: { accountId: '1' },
    query: { date: '2026-11-07T09:00:00' },
  });
  store = createStore({
    getters: {
      getCurrentAccountId: () => authority.account,
      getCurrentUserID: () => authority.actor,
      getCurrentRole: () => authority.role,
      getCurrentUser: () => ({
        id: authority.actor,
        accounts: [
          {
            id: authority.account,
            role: authority.role,
            availability: authority.presence,
          },
        ],
      }),
    },
    modules: {
      jrcCrm: {
        namespaced: true,
        modules: {
          activities: {
            ...activities,
            state: structuredClone(activities.state),
          },
        },
      },
    },
  });
  activitiesAPI.list.mockResolvedValue({ data: [source()] });
  activitiesAPI.complete.mockResolvedValue({
    data: { ...source(), completed_at: '2026-11-07T13:00:00Z' },
  });
  activitiesAPI.showInAccount.mockResolvedValue({ data: source() });
  activitiesAPI.updateInAccount.mockResolvedValue({ data: source() });
});
afterEach(() => wrapper?.unmount());
const render = async () => {
  wrapper = mount(CalendarView, {
    global: {
      plugins: [store],
      stubs: { RouterLink: true, CrmPageHeader: true, Dialog },
    },
  });
  await flushPromises();
};
const openEditor = async () => {
  await wrapper
    .findAll('button')
    .find(button => button.text().includes('Reagendar'))
    .trigger('click');
  await flushPromises();
};

it('reuses the real versioned editor and refreshes the native calendar after a persisted reschedule', async () => {
  await render();
  await openEditor();
  expect(activitiesAPI.showInAccount).toHaveBeenCalledWith('1', 1, {
    signal: expect.any(AbortSignal),
  });
  await wrapper
    .get('[data-testid="activity-due"]')
    .setValue('2026-11-09T10:15:12');
  const due = wrapper.get('[data-testid="activity-due"]');
  expect(due.element.valueAsNumber).toBe(Date.parse('2026-11-09T10:15:12Z'));
  const submittedDate = due.element.value;
  wrapper.findComponent(Dialog).vm.$emit('confirm');
  await flushPromises();
  expect(activitiesAPI.updateInAccount).toHaveBeenCalledWith(
    '1',
    1,
    {
      expected_version: source().edit_version,
      activity: {
        title: source().title,
        description: source().description,
        due_at: submittedDate,
      },
    },
    { signal: expect.any(AbortSignal) }
  );
  expect(activitiesAPI.list).toHaveBeenCalledTimes(2);
  expect(wrapper.findComponent(ActivityEditDialog).exists()).toBe(false);
});

it('does not duplicate native completion through the card and sidebar while the first write is pending', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('article button').trigger('click');
  const buttons = wrapper
    .findAll('button')
    .filter(button => button.text() === 'Concluir');
  expect(buttons.every(button => button.element.disabled)).toBe(true);
  await buttons[buttons.length - 1].trigger('click');
  expect(activitiesAPI.complete).toHaveBeenCalledTimes(1);
  finish({ data: source() });
  await flushPromises();
});

it('does not reload a replacement account after an obsolete completion receipt', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('article button').trigger('click');
  authority.account = 2;
  navigation.route.params.accountId = '2';
  await flushPromises();
  const requests = activitiesAPI.list.mock.calls.length;
  finish({ data: source() });
  await flushPromises();
  expect(activitiesAPI.list).toHaveBeenCalledTimes(requests);
});

it('shows a rejected completion and permits an explicit retry without fabricating success', async () => {
  activitiesAPI.complete.mockRejectedValueOnce({ response: { status: 403 } });
  await render();
  await wrapper.get('article button').trigger('click');
  await flushPromises();
  expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
  await wrapper.get('article button').trigger('click');
  await flushPromises();
  expect(activitiesAPI.complete).toHaveBeenCalledTimes(2);
  expect(activitiesAPI.list).toHaveBeenCalledTimes(2);
  expect(wrapper.find('[role="alert"]').exists()).toBe(false);
});

it('does not reload the native calendar after unmounting a pending completion', async () => {
  let finish;
  activitiesAPI.complete.mockImplementationOnce(
    () =>
      new Promise(resolve => {
        finish = resolve;
      })
  );
  await render();
  await wrapper.get('article button').trigger('click');
  wrapper.unmount();
  finish({ data: source() });
  await flushPromises();
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
});

it('reloads native visibility and closes the editor when the effective role changes', async () => {
  await render();
  await openEditor();
  authority.role = 'administrator';
  await flushPromises();
  expect(wrapper.findComponent(ActivityEditDialog).exists()).toBe(false);
  expect(activitiesAPI.list).toHaveBeenCalledTimes(2);
});

it('preserves the real editor draft through a native presence-only change', async () => {
  await render();
  await openEditor();
  await wrapper
    .get('[data-testid="activity-title"]')
    .setValue('Retained appointment draft');
  authority.presence = 'offline';
  await flushPromises();
  expect(wrapper.get('[data-testid="activity-title"]').element.value).toBe(
    'Retained appointment draft'
  );
  expect(activitiesAPI.list).toHaveBeenCalledTimes(1);
  expect(activitiesAPI.showInAccount).toHaveBeenCalledTimes(1);
});
