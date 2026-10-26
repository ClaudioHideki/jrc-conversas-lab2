import { shallowMount, flushPromises } from '@vue/test-utils';
import CollaboratorsPage from './CollaboratorsPage.vue';

const mocks = vi.hoisted(() => ({
  hasV2: true,
  dispatch: vi.fn(),
  get: vi.fn(),
  getInboxPolicy: vi.fn(),
  getInboxDiagnostics: vi.fn(),
  setInboxPolicy: vi.fn(),
  push: vi.fn(),
}));

vi.mock('vuex', () => ({
  useStore: () => ({
    dispatch: mocks.dispatch,
    getters: {
      'agents/getAgents': [],
      'accounts/isFeatureEnabledonAccount': (id, feature) =>
        feature === 'assignment_v2' && mocks.hasV2,
    },
  }),
}));
vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, path: '/app/accounts/1' }),
  useRouter: () => ({ push: mocks.push }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false }),
}));
vi.mock('dashboard/api/assignmentPolicies', () => ({
  default: {
    get: mocks.get,
    getInboxPolicy: mocks.getInboxPolicy,
    getInboxDiagnostics: mocks.getInboxDiagnostics,
    setInboxPolicy: mocks.setInboxPolicy,
  },
}));

const mountPage = () =>
  shallowMount(CollaboratorsPage, {
    props: { inbox: { id: 7, enable_auto_assignment: true } },
    global: {
      mocks: { $t: key => key },
      stubs: {
        SettingsAccordion: { template: '<div><slot /></div>' },
        SettingsFieldSection: { template: '<div><slot /></div>' },
        SettingsToggleSection: {
          template: '<div><slot name="editor" /></div>',
        },
        NextButton: {
          props: ['label'],
          emits: ['click'],
          template:
            '<button @click="$emit(\'click\')">{{ label }}<slot /></button>',
        },
        DropdownMenu: {
          props: ['menuItems'],
          template:
            '<button data-test="choose-policy" @click="$emit(\'action\', menuItems[0])">Choose</button>',
        },
      },
    },
  });

describe('Inbox assignment configuration', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.hasV2 = true;
    mocks.dispatch.mockResolvedValue({ data: { payload: [] } });
    mocks.get.mockResolvedValue({ data: [] });
    mocks.getInboxPolicy.mockRejectedValue({ response: { status: 404 } });
    mocks.getInboxDiagnostics.mockResolvedValue({
      data: { reason: 'policy_missing', agent_reasons: {} },
    });
    mocks.setInboxPolicy.mockResolvedValue({ data: {} });
  });

  it('shows the policy blocker in basic V2 without requiring advanced assignment', async () => {
    const wrapper = mountPage();
    await flushPromises();

    expect(mocks.getInboxPolicy).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain(
      'INBOX_MGMT.ASSIGNMENT.POLICY_MISSING_DESCRIPTION'
    );
    expect(wrapper.text()).not.toContain('DEFAULT_POLICY_LINKED');
    expect(mocks.setInboxPolicy).not.toHaveBeenCalled();
  });

  it('requires an explicit administrative action to link an existing policy', async () => {
    const policy = { id: 11, name: 'Synthetic policy' };
    mocks.get.mockResolvedValue({ data: [policy] });
    const wrapper = mountPage();
    await flushPromises();
    const linkButton = wrapper
      .findAll('button')
      .find(button => button.text().includes('LINK_EXISTING_POLICY'));
    expect(linkButton).toBeDefined();
    expect(mocks.setInboxPolicy).not.toHaveBeenCalled();
    expect(wrapper.find('[data-test="choose-policy"]').exists()).toBe(false);
    await linkButton.trigger('click');
    expect(mocks.setInboxPolicy).not.toHaveBeenCalled();
    await wrapper.get('[data-test="choose-policy"]').trigger('click');
    await flushPromises();

    expect(mocks.setInboxPolicy).toHaveBeenCalledExactlyOnceWith(7, 11);
    expect(wrapper.text()).toContain('Synthetic policy');
    expect(mocks.dispatch).not.toHaveBeenCalledWith(
      'inboxes/updateInbox',
      expect.anything()
    );
  });

  it('distinguishes a failed policy lookup from a confirmed missing policy', async () => {
    mocks.getInboxPolicy.mockRejectedValue({ response: { status: 503 } });
    const wrapper = mountPage();
    await flushPromises();

    expect(wrapper.text()).toContain('INBOX_MGMT.ASSIGNMENT.POLICY_LOAD_ERROR');
    expect(wrapper.text()).not.toContain('POLICY_MISSING_DESCRIPTION');
  });

  it('preserves the legacy settings when Assignment V2 is disabled', async () => {
    mocks.hasV2 = false;
    const wrapper = mountPage();
    await flushPromises();

    expect(mocks.getInboxPolicy).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain('POLICY_MISSING_DESCRIPTION');
  });
});
