import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import TeamsAPI from 'dashboard/api/teams';
import CustomRoleAPI from 'dashboard/api/customRole';
import AdministrationSection from './AdministrationSection.vue';
import ControlDeskPage from '../views/ControlDeskPage.vue';

const mocks = vi.hoisted(() => ({ route: null, replace: vi.fn() }));
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
  capabilities: { configure: true },
  units: [{ id: 1, name: 'Authorized' }],
  queues: [],
  corporate: { companies: [], units: [] },
};
const mountSection = (key = 'general', state = 'available') =>
  mount(AdministrationSection, {
    props: { accountId: '1', card: { key, state }, context },
    global: { stubs: { Dialog, RouterLink: true } },
  });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.route = reactive({ params: { accountId: '1' }, query: {} });
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
    mountSection('queues');
    await flushPromises();
    expect(API.administrativeList).toHaveBeenCalledWith(
      '1',
      'teams',
      expect.objectContaining({ q: 'support' })
    );
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
