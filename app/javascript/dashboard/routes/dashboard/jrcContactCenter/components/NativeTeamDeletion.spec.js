import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { createStore } from 'vuex';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import TeamsHome from 'dashboard/routes/dashboard/settings/teams/Index.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  remove: vi.fn(),
  alert: vi.fn(),
}));
vi.mock('vue-router', async original => ({
  ...(await original()),
  useRoute: () => mocks.route,
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);
const error = () => ({
  response: {
    status: 409,
    data: {
      error: 'team_deletion_confirmation_required',
      review: {
        account_id: '1',
        team_id: '2',
        team_name: 'SYNTHETIC delete team',
        operation: 'delete_team',
        queues: [
          {
            queue_id: '4',
            unit_id: '5',
            queue_name: 'SYNTHETIC last-agent queue',
            previous_count: 1,
            remaining_count: 0,
          },
        ],
        review_token: 'SYNTHETIC deletion receipt',
      },
    },
  },
});
const Dialog = defineComponent({
  emits: ['close'],
  setup(_props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
        emit('close');
      },
    });
    return { visible };
  },
  template:
    '<section v-if="visible" data-native-team-review-dialog><slot /></section>',
});
const render = () => {
  const store = createStore({
    state: () => ({
      user: { id: 7, accounts: [{ id: 1, role: 'administrator' }] },
    }),
    getters: {
      getCurrentUser: state => state.user,
      getCurrentRole: () => 'administrator',
      'teams/getTeams': () => [{ id: 2, name: 'SYNTHETIC delete team' }],
      'teams/getUIFlags': () => ({ isFetching: false }),
    },
    actions: { 'teams/delete': mocks.remove },
  });
  return mount(TeamsHome, {
    global: {
      plugins: [store],
      mocks: { $t: key => key },
      directives: { tooltip: () => {} },
      stubs: {
        BaseSettingsHeader: true,
        Icon: true,
        EmojiIcon: true,
        RouterLink: true,
        Dialog,
        'woot-confirm-delete-modal': {
          name: 'NativeDeleteConfirmation',
          emits: ['onConfirm', 'onClose', 'update:show'],
          template: '<section data-generic-native-delete />',
        },
      },
    },
  });
};
beforeEach(() => {
  vi.clearAllMocks();
  mocks.remove.mockReset();
  mocks.route = reactive({ params: { accountId: '1' } });
});

describe('existing team deletion page and separate manager review', () => {
  it('retains the generic native deletion confirmation before requesting the queue-impact review', async () => {
    mocks.remove.mockRejectedValueOnce(error()).mockResolvedValueOnce({});
    const wrapper = render();
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    expect(mocks.remove).not.toHaveBeenCalled();
    wrapper
      .findComponent({ name: 'NativeDeleteConfirmation' })
      .vm.$emit('onConfirm');
    await flushPromises();
    expect(wrapper.find('[data-generic-native-delete]').exists()).toBe(false);
    expect(
      wrapper.get('[data-team-roster-withdrawal-review]').text()
    ).toContain('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DELETE_TITLE');
    expect(mocks.alert).not.toHaveBeenCalled();
    await wrapper.get('[data-team-manager-withdrawal-confirm]').setValue(true);
    await wrapper.get('[data-apply-team-withdrawal]').trigger('click');
    await flushPromises();
    expect(mocks.remove.mock.calls[1][1]).toEqual({
      id: 2,
      accountId: '1',
      managerConfirmation: {
        confirmed: true,
        review_token: 'SYNTHETIC deletion receipt',
      },
    });
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
    expect(mocks.alert).toHaveBeenCalledWith(
      'TEAMS_SETTINGS.DELETE.API.SUCCESS_MESSAGE'
    );
  });

  it('does not repeat deletion until the review checkbox is explicitly confirmed', async () => {
    mocks.remove.mockRejectedValueOnce(error());
    const wrapper = render();
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    wrapper
      .findComponent({ name: 'NativeDeleteConfirmation' })
      .vm.$emit('onConfirm');
    await flushPromises();
    expect(
      wrapper.get('[data-apply-team-withdrawal]').attributes('disabled')
    ).toBeDefined();
    await wrapper.get('[data-apply-team-withdrawal]').trigger('click');
    expect(mocks.remove).toHaveBeenCalledTimes(1);
  });

  it('cancels the manager review without deleting the team or retaining its approval on reopening', async () => {
    mocks.remove.mockRejectedValueOnce(error());
    const wrapper = render();
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    wrapper
      .findComponent({ name: 'NativeDeleteConfirmation' })
      .vm.$emit('onConfirm');
    await flushPromises();
    await wrapper.get('[data-team-manager-withdrawal-confirm]').setValue(true);
    wrapper.vm.closeDelete();
    await flushPromises();
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    expect(wrapper.find('[data-generic-native-delete]').exists()).toBe(true);
    expect(mocks.remove).toHaveBeenCalledTimes(1);
  });

  it('ignores a late review after switching account and does not send a second deletion', async () => {
    let reject;
    mocks.remove.mockImplementationOnce(
      () =>
        new Promise((_resolve, decline) => {
          reject = decline;
        })
    );
    const wrapper = render();
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    wrapper
      .findComponent({ name: 'NativeDeleteConfirmation' })
      .vm.$emit('onConfirm');
    mocks.route.params.accountId = '9';
    reject(error());
    await flushPromises();
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
    expect(mocks.remove).toHaveBeenCalledTimes(1);
    expect(mocks.alert).not.toHaveBeenCalled();
  });

  it('blocks duplicate clicks while the existing native delete request is in flight', async () => {
    let resolve;
    mocks.remove.mockImplementationOnce(
      () =>
        new Promise(accept => {
          resolve = accept;
        })
    );
    const wrapper = render();
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    wrapper
      .findComponent({ name: 'NativeDeleteConfirmation' })
      .vm.$emit('onConfirm');
    wrapper.vm.deleteTeam();
    expect(mocks.remove).toHaveBeenCalledTimes(1);
    resolve({});
    await flushPromises();
    expect(mocks.alert).toHaveBeenCalledWith(
      'TEAMS_SETTINGS.DELETE.API.SUCCESS_MESSAGE'
    );
  });

  it('keeps an uncertain failure visible for manual recovery without retrying or marking deletion as successful', async () => {
    mocks.remove
      .mockRejectedValueOnce(error())
      .mockRejectedValueOnce(new Error('SYNTHETIC network failure'));
    const wrapper = render();
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    wrapper
      .findComponent({ name: 'NativeDeleteConfirmation' })
      .vm.$emit('onConfirm');
    await flushPromises();
    await wrapper.get('[data-team-manager-withdrawal-confirm]').setValue(true);
    await wrapper.get('[data-apply-team-withdrawal]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      true
    );
    expect(mocks.remove).toHaveBeenCalledTimes(2);
    expect(mocks.alert).toHaveBeenCalledWith(
      'TEAMS_SETTINGS.DELETE.API.ERROR_MESSAGE'
    );
  });
  it('explains a native relationship restriction without marking the team as deleted', async () => {
    mocks.remove.mockRejectedValueOnce({
      response: { status: 409, data: { error: 'team_in_use' } },
    });
    const wrapper = render();
    await wrapper.get('[data-team-delete="2"]').trigger('click');
    wrapper
      .findComponent({ name: 'NativeDeleteConfirmation' })
      .vm.$emit('onConfirm');
    await flushPromises();
    expect(mocks.alert).toHaveBeenCalledWith(
      'JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.DELETE_IN_USE'
    );
    expect(mocks.remove).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-team-delete="2"]').exists()).toBe(true);
  });
});
