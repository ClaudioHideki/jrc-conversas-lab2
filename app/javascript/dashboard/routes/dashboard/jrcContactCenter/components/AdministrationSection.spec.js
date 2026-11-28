import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import TeamsAPI from 'dashboard/api/teams';
import CustomRoleAPI from 'dashboard/api/customRole';
import AdministrationSection from './AdministrationSection.vue';
import ControlDeskPage from '../views/ControlDeskPage.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn(), user: null }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mocks.user,
}));
vi.mock('vue-router', () => ({
  useRoute: () => mocks.route,
  useRouter: () => ({ replace: mocks.replace }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    administration: vi.fn(),
    units: vi.fn(),
    queues: vi.fn(),
    queueMemberships: vi.fn(),
    administrativeList: vi.fn(),
    configurationRecord: vi.fn(),
    saveUnit: vi.fn(),
    saveQueue: vi.fn(),
    saveQueueMembership: vi.fn(),
    acwPolicy: vi.fn(),
    updateAcwPolicy: vi.fn(),
  },
}));
vi.mock('dashboard/api/teams', () => ({
  default: {
    create: vi.fn(),
    update: vi.fn(),
    getAgents: vi.fn(),
    updateAgents: vi.fn(),
  },
}));
vi.mock('dashboard/api/customRole', () => ({ default: { get: vi.fn() } }));
const Dialog = defineComponent({
  emits: ['confirm'],
  setup(_props, { expose, emit }) {
    const visible = ref(false);
    expose({
      open: () => {
        visible.value = true;
      },
      close: () => {
        visible.value = false;
      },
    });
    return { visible, confirm: () => emit('confirm'), label: 'SAVE' };
  },
  template:
    '<form v-if="visible" data-dialog @submit.prevent="confirm"><slot /><button data-submit type="submit">{{ label }}</button></form>',
});
enableAutoUnmount(afterEach);
const context = {
  capabilities: { configure: true, configuration_global: true },
  units: [{ id: 1, name: 'Authorized' }],
  queues: [],
  corporate: { companies: [], units: [] },
};
const mountSection = (key = 'general', state = 'available') =>
  mount(AdministrationSection, {
    props: { accountId: '1', card: { key, state }, context },
    global: {
      stubs: {
        Dialog,
        RouterLink: true,
        EndingScopedRuleEditor: {
          props: ['accountId'],
          emits: ['close'],
          template:
            '<section data-scoped-rule-dialog><span>{{ accountId }}</span><button data-scoped-rule-close @click="$emit(\'close\')">Close</button></section>',
        },
      },
    },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
  mocks.user = ref({
    id: 4,
    type: 'User',
    accounts: [{ id: 1, role: 'administrator', permissions: [] }],
  });
  API.units.mockResolvedValue({
    data: { items: [], meta: { page: 1, pages: 0, total: 0 } },
  });
  API.queues.mockResolvedValue({ data: { items: [] } });
  API.saveUnit.mockResolvedValue({ data: {} });
  API.administrativeList.mockResolvedValue({
    data: { items: [], agents: [], can_manage: true },
  });
});

describe('administrative workflow', () => {
  it('shows the authorized local availability and scoped count meaning without claiming an applied PABX state', async () => {
    API.administration.mockResolvedValueOnce({
      data: {
        cards: [
          {
            key: 'hours',
            state: 'pending_contract',
            local_state: 'available',
            count: null,
          },
          { key: 'closures', state: 'available', local_state: null, count: 0 },
        ],
        capabilities: {},
        provider: { configured: false },
      },
    });
    const wrapper = mount(ControlDeskPage, {
      global: {
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
          RecentConfigurationActivity: true,
        },
      },
    });
    await flushPromises();
    expect(wrapper.get('[data-card="hours"] [data-card-state]').text()).toBe(
      'JRC_CONTACT_CENTER.ADMIN.STATES.available'
    );
    expect(
      wrapper.get('[data-card="closures"] [data-card-count-label]').text()
    ).toBe('JRC_CONTACT_CENTER.ADMIN.PENDING_ACW_COUNT');
    expect(wrapper.get('[data-provider-state]').text()).toBe(
      'JRC_CONTACT_CENTER.ADMIN.CONNECTION_MISSING'
    );
  });

  it('provides the native recordings route only with its current independent view authority and does not call an unsupported generic list', async () => {
    const wrapper = mount(AdministrationSection, {
      props: {
        accountId: '1',
        card: { key: 'recordings', state: 'pending_contract' },
        context,
      },
      global: {
        stubs: {
          Dialog,
          RouterLink: {
            props: { to: { type: [Object, String], required: true } },
            template: '<a :data-route-name="to.name"><slot /></a>',
          },
        },
      },
    });
    await wrapper.setProps({
      card: {
        key: 'recordings',
        state: 'pending_contract',
        local_state: 'read_only',
      },
      context: {
        ...context,
        capabilities: { configure: false, recordings_view: true },
      },
    });
    await flushPromises();
    const link = wrapper.getComponent('[data-native-recordings-entry]');
    expect(link.props('to')).toEqual({
      name: 'jrc_contact_center_recordings',
      params: { accountId: '1' },
      query: {},
    });
    expect(wrapper.find('[data-create]').exists()).toBe(false);
    expect(API.administrativeList).not.toHaveBeenCalled();
    await wrapper.setProps({
      context: { ...context, capabilities: { recordings_view: false } },
    });
    expect(wrapper.find('[data-native-recordings-entry]').exists()).toBe(false);
  });

  it('distinguishes a usable local draft from the still pending provider operation without enabling generic create or publish', async () => {
    const wrapper = mountSection('ivr', 'pending_contract');
    await wrapper.setProps({
      card: { key: 'ivr', state: 'pending_contract', local_state: 'available' },
    });
    await flushPromises();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ADMIN.LOCAL_PROVIDER_PENDING'
    );
    expect(wrapper.text()).not.toContain('JRC_CONTACT_CENTER.ADMIN.PENDING');
    expect(wrapper.find('[data-create], [data-publish]').exists()).toBe(false);
    expect(API.administrativeList).not.toHaveBeenCalled();
  });

  it('opens only the scoped rule editor and resets its reviewed context on account changes', async () => {
    const wrapper = mountSection('closures');
    await wrapper.setProps({
      context: {
        ...context,
        capabilities: { configure: true, configuration_global: false },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-manage-ending-reasons]').exists()).toBe(false);
    expect(wrapper.find('[data-manage-acw-forms]').exists()).toBe(false);
    await wrapper.get('[data-manage-scoped-ending-rules]').trigger('click');
    expect(wrapper.get('[data-scoped-rule-dialog]').text()).toContain('1');
    await wrapper.setProps({ accountId: '2' });
    expect(wrapper.find('[data-scoped-rule-dialog]').exists()).toBe(false);
    await wrapper.get('[data-manage-scoped-ending-rules]').trigger('click');
    expect(wrapper.get('[data-scoped-rule-dialog]').text()).toContain('2');
    await wrapper.get('[data-scoped-rule-close]').trigger('click');
    expect(wrapper.find('[data-scoped-rule-dialog]').exists()).toBe(false);
    expect(API.acwPolicy).not.toHaveBeenCalled();
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
  });

  it('removes an opened scoped editor when native configuration authority is withdrawn', async () => {
    const wrapper = mountSection('closures');
    await wrapper.setProps({
      context: {
        ...context,
        capabilities: { configure: true, configuration_global: false },
      },
    });
    await wrapper.get('[data-manage-scoped-ending-rules]').trigger('click');
    expect(wrapper.find('[data-scoped-rule-dialog]').exists()).toBe(true);
    await wrapper.setProps({
      context: {
        ...context,
        capabilities: { configure: false, configuration_global: false },
      },
    });
    expect(wrapper.find('[data-scoped-rule-dialog]').exists()).toBe(false);
    expect(wrapper.find('[data-manage-scoped-ending-rules]').exists()).toBe(
      false
    );
    expect(API.acwPolicy).not.toHaveBeenCalled();
  });

  it('does not offer a global ACW change to an operator restricted to a unit', async () => {
    const wrapper = mountSection('closures');
    await wrapper.setProps({
      context: {
        ...context,
        capabilities: { configure: true, configuration_global: false },
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-create]').exists()).toBe(false);
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.ADMIN.ACW_GLOBAL_DENIED'
    );
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
  });

  it.each([
    ['ineligible_member', 'ENROLLMENT_BLOCKED'],
    ['member_scope_mismatch', 'ENROLLMENT_SCOPE'],
  ])(
    'preserves the queue draft when enrollment is rejected: %s',
    async (code, message) => {
      mocks.route.query = { queues_tab: 'memberships' };
      API.queueMemberships.mockResolvedValue({
        data: {
          items: [],
          agents: [
            { account_user_id: '8', name: 'Pending', eligible: false },
            { account_user_id: '9', name: 'Eligible', eligible: true },
          ],
        },
      });
      API.saveQueueMembership.mockRejectedValueOnce({
        response: { data: { error: code } },
      });
      const wrapper = mountSection('queues');
      await flushPromises();
      await wrapper.get('[data-create]').trigger('click');
      await flushPromises();
      expect(wrapper.get('option[value="8"]').element.disabled).toBe(true);
      await wrapper.get('[name="account_user_id"]').setValue('9');
      await wrapper.get('[data-dialog]').trigger('submit');
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toBe(
        `JRC_CONTACT_CENTER.ACCESS.${message}`
      );
      expect(wrapper.get('[name="account_user_id"]').element.value).toBe('9');
      expect(
        wrapper.get('[name="account_user_id"]').attributes('aria-invalid')
      ).toBe('true');
    }
  );

  it('keeps an unavailable native recipient disabled with an accurate enrollment label', async () => {
    mocks.route.query = { queues_tab: 'memberships' };
    API.queueMemberships.mockResolvedValue({
      data: {
        items: [],
        agents: [
          {
            account_user_id: '8',
            name: 'SYNTHETIC unavailable',
            eligible: false,
          },
        ],
      },
    });
    const wrapper = mountSection('queues');
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    const option = wrapper.get('option[value="8"]');
    expect(option.element.disabled).toBe(true);
    expect(option.text()).toContain(
      'JRC_CONTACT_CENTER.ACCESS.ENROLLMENT_UNAVAILABLE'
    );
    expect(API.saveQueueMembership).not.toHaveBeenCalled();
  });

  it('does not load a native role editor without the server capability', async () => {
    const wrapper = mountSection('permissions', 'native_module');
    await flushPromises();
    expect(CustomRoleAPI.get).not.toHaveBeenCalled();
    expect(wrapper.find('[data-edit-native-role]').exists()).toBe(false);
  });

  it('loads authorized native profiles and keeps role load failures visible', async () => {
    CustomRoleAPI.get.mockRejectedValueOnce(new Error('Unavailable'));
    const wrapper = mount(AdministrationSection, {
      props: {
        accountId: '1',
        card: { key: 'permissions', state: 'native_module' },
        context: {
          ...context,
          native_links: { permissions: true, role_editor: true },
        },
      },
      global: { stubs: { Dialog, RouterLink: true } },
    });
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
    expect(wrapper.find('[data-edit-native-role]').exists()).toBe(false);
  });

  it('does not close the native role editor when its form submit bubbles through the dialog', async () => {
    CustomRoleAPI.get.mockResolvedValue({
      data: [
        {
          id: 9,
          name: 'Scoped native profile',
          permissions: ['jrc_contact_center_view'],
        },
      ],
    });
    const wrapper = mount(AdministrationSection, {
      props: {
        accountId: '1',
        card: { key: 'permissions', state: 'native_module' },
        context: {
          ...context,
          native_links: { permissions: true, role_editor: true },
        },
      },
      global: { stubs: { Dialog, RouterLink: true, NativeRoleEditor: true } },
    });
    await flushPromises();
    await wrapper.get('select').setValue(9);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(true);
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(true);
    expect(API.saveUnit).not.toHaveBeenCalled();
  });

  it('preserves a failed creation draft and persists the reviewed values on retry', async () => {
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    const inputs = wrapper.findAll('[data-dialog] input');
    await inputs[0].setValue('Synthetic unit');
    await inputs[1].setValue('SYNTHETIC');
    API.saveUnit.mockRejectedValueOnce({
      response: { data: { message: 'Conflict' } },
    });
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe('Conflict');
    expect(inputs[0].element.value).toBe('Synthetic unit');
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.saveUnit).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ name: 'Synthetic unit', code: 'SYNTHETIC' }),
      undefined,
      {}
    );
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
  });

  it('edits loaded values without changing the list object before persistence', async () => {
    const unit = {
      id: 10,
      revision: 'a'.repeat(64),
      name: 'Original',
      code: 'ORIGINAL',
      kind: 'sac',
      timezone: 'UTC',
      status: 'active',
      settings: {},
    };
    API.units.mockResolvedValue({ data: { items: [unit] } });
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-dialog] input').setValue('Revised');
    expect(unit.name).toBe('Original');
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.saveUnit).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ name: 'Revised', timezone: 'UTC' }),
      10,
      { expected_revision: 'a'.repeat(64) }
    );
  });

  it('restores pagination and filters from the URL and clears them explicitly', async () => {
    mocks.route.query = {
      units_page: '2',
      units_q: 'finance',
      units_status: 'inactive',
    };
    const wrapper = mountSection();
    await flushPromises();
    expect(API.units).toHaveBeenCalledWith('1', {
      page: 2,
      per_page: 20,
      q: 'finance',
      status: 'inactive',
    });
    await wrapper.findAll('form button')[1].trigger('click');
    expect(mocks.replace).toHaveBeenCalledWith({
      query: { units_page: 1, units_q: undefined, units_status: undefined },
    });
  });

  it('does not present fake controls or counters for a pending provider capability', async () => {
    const wrapper = mountSection('ivr', 'pending_contract');
    await flushPromises();
    expect(wrapper.find('[data-create]').exists()).toBe(false);
    expect(wrapper.find('form').exists()).toBe(false);
    expect(API.administrativeList).not.toHaveBeenCalled();
    expect(wrapper.get('[role="status"]').text()).toBe(
      'JRC_CONTACT_CENTER.ADMIN.PENDING'
    );
  });

  it('prevents a repeated submit while persistence is in flight', async () => {
    let finish;
    API.saveUnit.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-dialog]').trigger('submit');
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.saveUnit).toHaveBeenCalledTimes(1);
    finish({ data: {} });
    await flushPromises();
  });

  it('announces a saved resource before awaiting its list reload', async () => {
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    const inputs = wrapper.findAll('[data-dialog] input');
    await inputs[0].setValue('Synthetic unit');
    await inputs[1].setValue('SYNTHETIC');
    let finish;
    API.units.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
    expect(wrapper.emitted('changed')).toHaveLength(1);
    finish({ data: { items: [], meta: { page: 1, pages: 0, total: 0 } } });
    await flushPromises();
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('announces a closed native role editor before awaiting its catalog reload', async () => {
    CustomRoleAPI.get.mockResolvedValue({
      data: [
        {
          id: 9,
          name: 'Native profile',
          permissions: ['jrc_contact_center_view'],
        },
      ],
    });
    const wrapper = mount(AdministrationSection, {
      props: {
        accountId: '1',
        card: { key: 'permissions', state: 'native_module' },
        context: {
          ...context,
          native_links: { permissions: true, role_editor: true },
        },
      },
      global: { stubs: { Dialog, RouterLink: true, NativeRoleEditor: true } },
    });
    await flushPromises();
    await wrapper.get('select').setValue(9);
    await wrapper.get('form').trigger('submit');
    await flushPromises();
    let finish;
    CustomRoleAPI.get.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    wrapper.findComponent({ name: 'NativeRoleEditor' }).vm.$emit('close');
    await flushPromises();
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
    expect(wrapper.emitted('changed')).toHaveLength(1);
    finish({ data: [] });
    await flushPromises();
    expect(wrapper.emitted('changed')).toHaveLength(1);
  });

  it('discards late administrative data after switching account', async () => {
    let finish;
    API.administration
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      )
      .mockResolvedValueOnce({
        data: { cards: [], capabilities: {}, provider: {} },
      });
    const wrapper = mount(ControlDeskPage, {
      global: { stubs: { RouterLink: true } },
    });
    mocks.route.params.accountId = '2';
    await flushPromises();
    finish({
      data: {
        cards: [{ key: 'general', state: 'available', count: 999 }],
        capabilities: { configure: true },
        provider: {},
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-card="general"]').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('999');
  });

  it('restores the selected native team tab from the URL', async () => {
    mocks.route.query = { queues_tab: 'teams', teams_q: 'support' };
    API.administrativeList.mockResolvedValueOnce({
      data: {
        items: [{ id: 25, name: 'SYNTHETIC existing team' }],
        agents: [],
        can_manage: true,
      },
    });
    TeamsAPI.getAgents.mockResolvedValueOnce({ data: [] });
    const wrapper = mountSection('queues');
    await flushPromises();
    expect(API.administrativeList).toHaveBeenCalledWith(
      '1',
      'teams',
      expect.objectContaining({ q: 'support' })
    );
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-dialog]').attributes('title')).toBe(
      'JRC_CONTACT_CENTER.ADMIN.RESOURCES.teams — JRC_CONTACT_CENTER.ADMIN.EDIT'
    );
    expect(wrapper.get('legend').classes()).toContain('text-n-slate-12');
  });

  it('preserves a non-voice queue channel while editing its name', async () => {
    API.queues.mockResolvedValue({
      data: {
        items: [
          {
            id: 12,
            revision: 'a'.repeat(64),
            name: 'Original',
            code: 'CHAT',
            unit_id: 1,
            service_kind: 'whatsapp',
            strategy: 'provider',
            status: 'active',
          },
        ],
      },
    });
    const wrapper = mountSection('queues');
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-dialog] input').setValue('Reviewed');
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.saveQueue).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ name: 'Reviewed', service_kind: 'whatsapp' }),
      12,
      { expected_revision: 'a'.repeat(64) }
    );
  });

  it('identifies backend-rejected fields without losing the draft', async () => {
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    await wrapper.get('[name="name"]').setValue('Reviewed');
    await wrapper.get('[name="code"]').setValue('DUPLICATE');
    API.saveUnit.mockRejectedValueOnce({
      response: { data: { message: 'Conflict', attributes: ['code'] } },
    });
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[name="code"]').attributes('aria-invalid')).toBe(
      'true'
    );
    expect(wrapper.get('[name="name"]').element.value).toBe('Reviewed');
  });

  it('clears an incompatible business unit after changing the issuer', async () => {
    const wrapper = mount(AdministrationSection, {
      props: {
        accountId: '1',
        card: { key: 'general', state: 'available' },
        context: {
          ...context,
          corporate: {
            companies: [
              { id: 10, name: 'A' },
              { id: 20, name: 'B' },
            ],
            units: [{ id: 11, name: 'Unit A', company_id: 10 }],
          },
        },
      },
      global: { stubs: { Dialog, RouterLink: true } },
    });
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    await wrapper.get('[name="issuer_company_id"]').setValue('10');
    await wrapper.get('[name="business_unit_id"]').setValue('11');
    await wrapper.get('[name="issuer_company_id"]').setValue('20');
    expect(wrapper.get('[name="business_unit_id"]').element.value).toBe('');
  });

  it('keeps team membership writes independent from the team fields and queue assignment', async () => {
    mocks.route.query = { queues_tab: 'teams' };
    API.administrativeList.mockResolvedValue({
      data: {
        items: [{ id: 4, name: 'Native team', description: 'Original' }],
        agents: [{ user_id: 8, name: 'Eligible member' }],
        can_manage: true,
      },
    });
    TeamsAPI.getAgents.mockResolvedValue({ data: [] });
    TeamsAPI.updateAgents.mockResolvedValue({ data: [] });
    const wrapper = mountSection('queues');
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-team-member="8"]').setValue(true);
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(TeamsAPI.update).not.toHaveBeenCalled();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.ADMIN.TEAM_MEMBERS_UNSAVED'
    );
    await wrapper.get('[data-save-team-members]').trigger('click');
    await flushPromises();
    expect(TeamsAPI.updateAgents).toHaveBeenCalledWith({
      teamId: 4,
      agentsList: [8],
    });
    expect(TeamsAPI.update).not.toHaveBeenCalled();
    expect(API.saveQueueMembership).not.toHaveBeenCalled();
    expect(wrapper.find('[data-dialog]').exists()).toBe(true);
  });

  it('keeps selected native team members on a failed write without granting queue roles', async () => {
    mocks.route.query = { queues_tab: 'teams' };
    API.administrativeList.mockResolvedValue({
      data: {
        items: [{ id: 4, name: 'Native team' }],
        agents: [{ user_id: 8, name: 'Eligible member' }],
        can_manage: true,
      },
    });
    TeamsAPI.getAgents.mockResolvedValue({ data: [] });
    TeamsAPI.updateAgents.mockRejectedValue({
      response: { data: { error: 'Denied' } },
    });
    const wrapper = mountSection('queues');
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-team-member="8"]').setValue(true);
    await wrapper.get('[data-save-team-members]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-team-member="8"]').element.checked).toBe(true);
    expect(wrapper.get('[role="alert"]').text()).toBe('Denied');
    expect(API.saveQueueMembership).not.toHaveBeenCalled();
  });

  it('requires explicit manager review before retrying a team removal and never sends a queue reassignment', async () => {
    mocks.route.query = { queues_tab: 'teams' };
    API.administrativeList.mockResolvedValue({
      data: {
        items: [{ id: 4, name: 'Native team' }],
        agents: [{ user_id: 8, name: 'Eligible member' }],
        can_manage: true,
      },
    });
    TeamsAPI.getAgents.mockResolvedValue({ data: [{ id: 8 }] });
    TeamsAPI.updateAgents
      .mockRejectedValueOnce({
        response: {
          status: 409,
          data: {
            error: 'team_roster_confirmation_required',
            review: {
              account_id: '1',
              team_id: '4',
              team_name: 'Native team',
              operation: 'update',
              queues: [
                {
                  queue_id: '2',
                  unit_id: '1',
                  queue_name: 'SYNTHETIC affected queue',
                  previous_count: 1,
                  remaining_count: 0,
                },
              ],
              review_token: 'synthetic-client-only-receipt',
            },
          },
        },
      })
      .mockResolvedValueOnce({ data: [] });
    const wrapper = mountSection('queues');
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-team-member="8"]').setValue(false);
    await wrapper.get('[data-save-team-members]').trigger('click');
    await flushPromises();
    expect(TeamsAPI.updateAgents).toHaveBeenCalledTimes(1);
    expect(wrapper.get('[data-save-team-members]').element.disabled).toBe(true);
    await wrapper.get('[data-team-manager-withdrawal-confirm]').setValue(true);
    await wrapper.get('[data-save-team-members]').trigger('click');
    await flushPromises();
    expect(TeamsAPI.updateAgents).toHaveBeenLastCalledWith({
      teamId: 4,
      agentsList: [],
      managerConfirmation: {
        confirmed: true,
        review_token: 'synthetic-client-only-receipt',
      },
    });
    expect(wrapper.find('[data-team-roster-withdrawal-review]').exists()).toBe(
      false
    );
    expect(API.saveQueueMembership).not.toHaveBeenCalled();
  });

  it('preserves a stale native unit draft and requires an explicitly reviewed reload before retry', async () => {
    API.units.mockResolvedValue({
      data: {
        items: [
          {
            id: 10,
            revision: 'a'.repeat(64),
            name: 'Original',
            code: 'REVIEW',
            kind: 'sac',
            timezone: 'UTC',
            status: 'active',
            settings: {},
          },
        ],
        meta: { page: 1, pages: 1, total: 1 },
      },
    });
    API.saveUnit.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    API.configurationRecord.mockResolvedValue({
      data: {
        item: {
          id: 10,
          revision: 'b'.repeat(64),
          name: 'Concurrent server version',
          code: 'REVIEW',
          settings: { private: 'DO-NOT-DISPLAY' },
        },
      },
    });
    const wrapper = mountSection();
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    await wrapper
      .get('[data-dialog] [name=name]')
      .setValue('Preserved reviewed draft');
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-configuration-conflict]').text()).toContain(
      'CONFIGURATION_REVISION.CONFLICT'
    );
    expect(wrapper.get('[data-dialog] [name=name]').element.value).toBe(
      'Preserved reviewed draft'
    );
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.saveUnit).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-configuration-conflict] button').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-configuration-latest]').text()).toContain(
      'Concurrent server version'
    );
    expect(wrapper.get('[data-configuration-latest]').text()).not.toContain(
      'DO-NOT-DISPLAY'
    );
    expect(wrapper.get('[data-dialog] [name=name]').element.value).toBe(
      'Preserved reviewed draft'
    );
    await wrapper.get('[data-configuration-review]').setValue(true);
    await wrapper
      .get('[data-dialog] [name=name]')
      .setValue('Changed after review');
    expect(wrapper.get('[data-configuration-review]').element.checked).toBe(
      false
    );
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.saveUnit).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-configuration-review]').setValue(true);
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.saveUnit).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ name: 'Changed after review' }),
      10,
      { expected_revision: 'b'.repeat(64) }
    );
    expect(wrapper.find('[data-dialog]').exists()).toBe(false);
  });
});

describe('global ACW administrative popup revision', () => {
  const policy = (revision, voice = 180) => ({
    id: '1',
    revision,
    limits: { voice, whatsapp: 180 },
    voice_required: false,
  });
  it('identifies ACW as policy configuration instead of a new native record', async () => {
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: policy('a'.repeat(64)) },
    });
    const wrapper = mountSection('closures');
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-dialog]').attributes('title')).toBe(
      'JRC_CONTACT_CENTER.ACW_RULES.CONFIGURATION_TITLE'
    );
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
  });
  it('preserves HH:MM input and compares both states in seconds before an explicit retry', async () => {
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: policy('a'.repeat(64)) },
    });
    API.acwPolicy.mockResolvedValueOnce({
      data: { item: policy('b'.repeat(64), 300) },
    });
    API.updateAcwPolicy.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    API.updateAcwPolicy.mockResolvedValueOnce({ data: {} });
    const wrapper = mountSection('closures');
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    await wrapper.get('[name="voice"]').setValue('00:04');
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.updateAcwPolicy).toHaveBeenCalledWith(
      '1',
      { voice: 240, whatsapp: 180 },
      { voice_required: false, expected_revision: 'a'.repeat(64) }
    );
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.updateAcwPolicy).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-configuration-conflict] button').trigger('click');
    await flushPromises();
    expect(wrapper.get('[name="voice"]').element.value).toBe('00:04');
    const compared = wrapper.get('[data-configuration-latest]').text();
    expect(compared).toContain('300');
    expect(compared).toContain('240');
    expect(compared).toContain('CONFIGURATION_AUDIT.NO');
    await wrapper.get('[data-configuration-review]').setValue(true);
    await wrapper.get('[name="voice"]').setValue('00:05');
    expect(wrapper.get('[data-configuration-review]').element.checked).toBe(
      false
    );
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.updateAcwPolicy).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-configuration-review]').setValue(true);
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.updateAcwPolicy).toHaveBeenLastCalledWith(
      '1',
      { voice: 300, whatsapp: 180 },
      { voice_required: false, expected_revision: 'b'.repeat(64) }
    );
  });
  it('does not bypass a missing native policy revision', async () => {
    API.acwPolicy.mockResolvedValueOnce({ data: { item: policy('') } });
    const wrapper = mountSection('closures');
    await flushPromises();
    await wrapper.get('[data-create]').trigger('click');
    await flushPromises();
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
    expect(wrapper.get('[data-configuration-conflict]').exists()).toBe(true);
  });

  it('passes only an explicitly confirmed review with the unchanged native membership draft', async () => {
    mocks.route.query = { queues_tab: 'memberships' };
    const row = {
      id: '2',
      queue_id: '3',
      queue_name: 'SYNTHETIC last queue',
      account_user_id: '4',
      user_name: 'SYNTHETIC operator',
      participates: true,
      supervises: false,
      active: true,
      priority: 10,
      revision: 'a'.repeat(64),
    };
    API.queueMemberships.mockResolvedValue({
      data: {
        items: [row],
        meta: { total: 1, page: 1, pages: 1 },
        agents: [
          { account_user_id: '4', name: 'SYNTHETIC operator', eligible: true },
        ],
      },
    });
    API.configurationRecord.mockResolvedValue({ data: { item: row } });
    API.saveQueueMembership.mockRejectedValueOnce({
      response: {
        data: {
          error: 'last_eligible_confirmation_required',
          review: {
            account_id: '1',
            membership_id: '2',
            queue_id: '3',
            queue_name: row.queue_name,
            previous_count: 1,
            remaining_count: 0,
            review_token: 'synthetic-client-only-receipt',
          },
        },
      },
    });
    API.saveQueueMembership.mockResolvedValueOnce({ data: {} });
    const wrapper = mountSection('queues');
    await flushPromises();
    await wrapper.get('[data-edit]').trigger('click');
    await flushPromises();
    const active = wrapper
      .findAll('label')
      .find(node => node.text() === 'JRC_CONTACT_CENTER.ADMIN.ACTIVE')
      .find('input');
    await active.setValue(false);
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('[data-queue-withdrawal-review]').exists()).toBe(true);
    expect(API.saveQueueMembership).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-dialog]').trigger('submit');
    expect(API.saveQueueMembership).toHaveBeenCalledTimes(1);
    await wrapper.get('[data-manager-withdrawal-confirm]').setValue(true);
    await wrapper.get('[data-dialog]').trigger('submit');
    await flushPromises();
    expect(API.saveQueueMembership).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ active: false }),
      '2',
      {
        expected_revision: 'a'.repeat(64),
        manager_confirmation: {
          confirmed: true,
          review_token: 'synthetic-client-only-receipt',
        },
      }
    );
  });
  it('shows the Call Center team source status without editing the native roster or hiding the team', async () => {
    mocks.route.query.queues_tab = 'teams';
    API.administrativeList.mockResolvedValue({
      data: {
        items: [{ id: 7, name: 'SYNTHETIC native team', cc_active: false }],
        can_manage: true,
      },
    });
    const wrapper = mountSection('queues');
    await wrapper.setProps({
      context: { ...context, native_links: { access_editor: true } },
    });
    await flushPromises();
    expect(wrapper.get('[data-team-source-status]').text()).toContain(
      'JRC_CONTACT_CENTER.ACCESS.TEAM_INACTIVE'
    );
    await wrapper.get('[data-manage-team-authority]').trigger('click');
    expect(mocks.replace).toHaveBeenCalledWith({
      name: 'jrc_contact_center_admin_section',
      params: { accountId: '1', section: 'permissions' },
      query: {
        permission_scope: 'teams',
        access_teams_q: 'SYNTHETIC native team',
        access_teams_page: 1,
      },
    });
    expect(TeamsAPI.updateAgents).not.toHaveBeenCalled();
  });

  it('does not expose team-source authorization management to a configure-only actor', async () => {
    mocks.route.query.queues_tab = 'teams';
    API.administrativeList.mockResolvedValue({
      data: {
        items: [{ id: 7, name: 'SYNTHETIC native team', cc_active: false }],
        can_manage: true,
      },
    });
    const wrapper = mountSection('queues');
    await flushPromises();
    expect(wrapper.find('[data-manage-team-authority]').exists()).toBe(false);
    expect(wrapper.get('[data-team-source-status]').text()).toContain(
      'JRC_CONTACT_CENTER.ACCESS.TEAM_INACTIVE'
    );
  });
});

describe('native PABX observation destination from the existing administrative card', () => {
  it('preserves query context and offers only the existing read-only route with current control capability', async () => {
    mocks.route.query.preserved = 'native-proof';
    const wrapper = mount(AdministrationSection, {
      props: {
        accountId: '1',
        card: { key: 'pabx', state: 'available' },
        context,
      },
      global: {
        stubs: {
          Dialog,
          RouterLink: { props: ['to'], template: '<a><slot /></a>' },
        },
      },
    });
    await flushPromises();
    expect(
      wrapper.getComponent('[data-native-pabx-observations-link]').props('to')
    ).toEqual({
      name: 'jrc_contact_center_pabx',
      params: { accountId: '1' },
      query: { preserved: 'native-proof' },
    });
    await wrapper.setProps({
      card: { key: 'approvals', state: 'native_module' },
      context: { ...context, native_links: { approvals: true } },
    });
    await flushPromises();
    expect(
      wrapper.getComponent('[data-native-contact-center-approvals]').props('to')
    ).toEqual({
      name: 'jrc_approvals',
      params: { accountId: '1' },
      query: { module_key: 'contact_center' },
    });
    expect(API.saveUnit).not.toHaveBeenCalled();
    expect(API.saveQueue).not.toHaveBeenCalled();
  });
  it('does not infer control or infrastructure access from native administrative card visibility', async () => {
    const wrapper = mountSection('pabx');
    await wrapper.setProps({
      context: {
        ...context,
        capabilities: { configure: false, supervise: false },
        native_links: {},
      },
    });
    await flushPromises();
    expect(wrapper.find('[data-native-pabx-observations-link]').exists()).toBe(
      false
    );
    expect(wrapper.find('[data-native-pabx-settings]').exists()).toBe(false);
    await wrapper.setProps({
      card: { key: 'approvals', state: 'native_module' },
    });
    await flushPromises();
    expect(
      wrapper.find('[data-native-contact-center-approvals]').exists()
    ).toBe(false);
  });
});

describe('native administrative counter errors remain independent from panel access', () => {
  const mountOverview = () =>
    mount(ControlDeskPage, {
      global: {
        stubs: {
          RouterLink: { template: '<a><slot /></a>' },
          RecentConfigurationActivity: true,
          AdministrationPendingAlerts: true,
        },
      },
    });
  const panel = count => ({
    data: {
      cards: [
        {
          key: 'queues',
          state: 'available',
          count,
          ...(count === 999 ? { count_error: true } : {}),
        },
        { key: 'general', state: 'available', count: 3 },
      ],
      capabilities: {},
      provider: { configured: false },
    },
  });

  it('keeps authorized native cards usable while marking one failed count without stale or fictitious zero', async () => {
    API.administration.mockReset().mockResolvedValue(panel(999));
    const wrapper = mountOverview();
    await flushPromises();
    expect(
      wrapper.get('[data-card="queues"] [data-card-count-error]').text()
    ).toBe('JRC_CONTACT_CENTER.ADMIN.COUNTER_UNAVAILABLE');
    expect(wrapper.get('[data-card="queues"]').text()).not.toContain('999');
    expect(wrapper.find('[data-card="queues"] .text-xl').exists()).toBe(false);
    expect(wrapper.get('[data-card="general"] .text-xl').text()).toBe('3');
  });

  it('retries through the existing panel refresh and distinguishes an observed zero from an unavailable count', async () => {
    API.administration
      .mockReset()
      .mockResolvedValueOnce(panel(999))
      .mockResolvedValueOnce(panel(0));
    const wrapper = mountOverview();
    await flushPromises();
    await wrapper.get('button').trigger('click');
    await flushPromises();
    expect(API.administration).toHaveBeenCalledTimes(2);
    expect(wrapper.find('[data-card-count-error]').exists()).toBe(false);
    expect(wrapper.get('[data-card="queues"] .text-xl').text()).toBe('0');
    expect(wrapper.get('[data-card="general"] .text-xl').text()).toBe('3');
  });
});
