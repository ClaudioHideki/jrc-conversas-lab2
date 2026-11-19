import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { createStore } from 'vuex';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { organizationStructureAPI } from 'dashboard/api/crm';
import teamsAPI from 'dashboard/api/teams';
import EditAgents from 'dashboard/routes/dashboard/settings/teams/Edit/EditAgents.vue';
import OrganizationalStructureSettings from 'dashboard/routes/dashboard/crm/views/settings/OrganizationalStructureSettings.vue';

const mocks = vi.hoisted(() => ({
  route: null,
  replace: vi.fn(),
  alert: vi.fn(),
  update: vi.fn(),
}));
vi.mock('dashboard/routes/index', () => ({
  default: { replace: mocks.replace },
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => mocks.route,
}));
vi.mock('dashboard/composables', () => ({ useAlert: mocks.alert }));
vi.mock('dashboard/api/crm', () => ({
  organizationStructureAPI: { load: vi.fn() },
}));
vi.mock('dashboard/api/teams', () => ({ default: { updateAgents: vi.fn() } }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
enableAutoUnmount(afterEach);

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

const error = () => ({
  response: {
    status: 409,
    data: {
      error: 'team_roster_confirmation_required',
      review: {
        account_id: '1',
        team_id: '2',
        team_name: 'SYNTHETIC team',
        operation: 'update',
        queues: [
          {
            queue_id: '4',
            unit_id: '5',
            queue_name: 'SYNTHETIC impacted queue',
            previous_count: 1,
            remaining_count: 0,
          },
        ],
        review_token: 'synthetic-client-only-receipt',
      },
    },
  },
});
const team = () => ({
  id: 2,
  name: 'SYNTHETIC team',
  members_count: 2,
  members: [
    { id: 3, name: 'Retained' },
    { id: 8, name: 'Removed' },
  ],
});
const store = () =>
  createStore({
    state: () => ({
      user: {
        id: 7,
        accounts: [{ id: 1, role: 'administrator', custom_role_id: null }],
      },
    }),
    getters: {
      getCurrentUser: state => state.user,
      'teams/getTeam': () => () => team(),
      'teamMembers/getTeamMembers': () => () => team().members,
      'teamMembers/getUIFlags': () => ({ isFetching: false }),
      'agents/getAgents': () => team().members,
    },
    actions: {
      'agents/get': vi.fn(),
      'teamMembers/get': vi.fn(),
      'teamMembers/update': mocks.update,
      'teams/get': vi.fn(),
    },
  });
const render = component =>
  mount(component, {
    global: {
      plugins: [store()],
      mocks: { $route: mocks.route, $t: key => key },
      stubs: {
        Dialog,
        Spinner: true,
        PageHeader: true,
        CorporateProfileFields: true,
        AgentSelector: {
          template: '<button type="submit" data-native-save>Save</button>',
        },
      },
    },
  });

beforeEach(() => {
  vi.clearAllMocks();
  mocks.update.mockReset();
  teamsAPI.updateAgents.mockReset();
  mocks.route = reactive({ params: { accountId: '1', teamId: '2' } });
  organizationStructureAPI.load.mockResolvedValue({
    data: {
      group: {},
      operating_companies: [],
      business_units: [],
      teams: [team()],
      users: [],
      team_scopes: [],
      user_scopes: [],
    },
  });
});

describe('existing native team editors', () => {
  it('preserves the legacy editor selection and waits for explicit review instead of navigating on a 409', async () => {
    mocks.update.mockRejectedValueOnce(error()).mockResolvedValueOnce({});
    const wrapper = render(EditAgents);
    await flushPromises();
    wrapper.vm.selectedAgents = [3];
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.vm.selectedAgents).toEqual([3]);
    expect(mocks.replace).not.toHaveBeenCalled();
    expect(mocks.alert).not.toHaveBeenCalled();
    expect(
      wrapper.get('[data-team-roster-withdrawal-review]').text()
    ).toContain('JRC_CONTACT_CENTER.TEAM_WITHDRAWAL.TITLE');
    await wrapper.get('[data-team-manager-withdrawal-confirm]').setValue(true);
    await wrapper.get('[data-apply-team-withdrawal]').trigger('click');
    await flushPromises();
    expect(mocks.update.mock.calls[1][1]).toEqual({
      teamId: '2',
      agentsList: [3],
      managerConfirmation: {
        confirmed: true,
        review_token: 'synthetic-client-only-receipt',
      },
    });
    expect(mocks.replace).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'settings_teams_edit_finish' })
    );
  });

  it('invalidates the legacy review after selection changes and preserves a failed retry for safe manual recovery', async () => {
    mocks.update
      .mockRejectedValueOnce(error())
      .mockRejectedValueOnce(new Error('SYNTHETIC network unavailable'));
    const wrapper = render(EditAgents);
    await flushPromises();
    wrapper.vm.selectedAgents = [3];
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    wrapper.vm.selectedAgents = [3, 8];
    await flushPromises();
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(mocks.update.mock.calls[1][1]).not.toHaveProperty(
      'managerConfirmation'
    );
    expect(wrapper.vm.selectedAgents).toEqual([3, 8]);
    expect(mocks.alert).toHaveBeenCalledWith('SYNTHETIC network unavailable');
    expect(mocks.replace).not.toHaveBeenCalled();
  });

  it('does not display a late legacy review after changing the account context', async () => {
    let reject;
    mocks.update.mockImplementationOnce(
      () =>
        new Promise((_resolve, decline) => {
          reject = decline;
        })
    );
    const wrapper = render(EditAgents);
    await flushPromises();
    wrapper.vm.selectedAgents = [3];
    await wrapper.get('form').trigger('submit');
    mocks.route.params.accountId = '9';
    reject(error());
    await flushPromises();
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
    expect(mocks.replace).not.toHaveBeenCalled();
  });

  it('lets the existing CRM editor explicitly confirm the same native removal and reload persisted data', async () => {
    teamsAPI.updateAgents
      .mockRejectedValueOnce(error())
      .mockResolvedValueOnce({ data: [] });
    const wrapper = render(OrganizationalStructureSettings);
    await flushPromises();
    await wrapper
      .findAll('[aria-label="CRM.ORGANIZATION.REMOVE_MEMBER"]')[1]
      .trigger('click');
    await flushPromises();
    expect(teamsAPI.updateAgents).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-team-roster-withdrawal-review]').exists()).toBe(
      true
    );
    await wrapper.get('[data-team-manager-withdrawal-confirm]').setValue(true);
    await wrapper.get('[data-apply-team-withdrawal]').trigger('click');
    await flushPromises();
    expect(teamsAPI.updateAgents).toHaveBeenLastCalledWith({
      teamId: 2,
      agentsList: [3],
      managerConfirmation: {
        confirmed: true,
        review_token: 'synthetic-client-only-receipt',
      },
    });
    expect(organizationStructureAPI.load).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
  });

  it('cancels the CRM review without sending another request or losing the stored roster', async () => {
    teamsAPI.updateAgents.mockRejectedValueOnce(error());
    const wrapper = render(OrganizationalStructureSettings);
    await flushPromises();
    await wrapper
      .findAll('[aria-label="CRM.ORGANIZATION.REMOVE_MEMBER"]')[1]
      .trigger('click');
    await flushPromises();
    const cancel = wrapper
      .get('[data-team-roster-withdrawal-review]')
      .findAll('button')[1];
    await cancel.trigger('click');
    expect(teamsAPI.updateAgents).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('Removed');
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
  });
});
