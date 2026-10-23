import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, reactive, ref } from 'vue';
import { createStore } from 'vuex';
import { createPinia } from 'pinia';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import JrcContactCenterAPI from 'dashboard/api/jrcContactCenter';
import InboxList from './InboxList.vue';
import { routes as webphoneRoutes } from '../webphone/routes';
import { openEmbeddedSoftphone } from '../webphone/useEmbeddedSoftphone';

const mocks = vi.hoisted(() => ({ route: null, router: null, sip: null }));
vi.mock('dashboard/routes/dashboard/webphone/useSipWebphone', () => ({
  useSipWebphone: () => mocks.sip,
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => mocks.route,
  useRouter: () => mocks.router,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { calls: vi.fn(), context: vi.fn(), agentState: vi.fn() },
}));
enableAutoUnmount(afterEach);

const ConversationPanel = defineComponent({
  setup: () => ({ account: mocks.route.params.accountId }),
  template: '<div data-testid="conversation-panel">{{ account }}</div>',
});
const call = {
  id: 7,
  ani: '+550000000001',
  direction: 'inbound',
  status: 'connected',
};
let store;

const mountInbox = () =>
  mount(InboxList, {
    global: {
      plugins: [store, createPinia()],
      stubs: {
        Dialog: { methods: { open() {}, close() {} }, template: '<div />' },
        RouterLink: {
          name: 'RouterLink',
          props: ['to'],
          template: '<a><slot /></a>',
        },
        RouterView: ConversationPanel,
        Spinner: { template: '<div data-testid="loading" />' },
        ConversationCard: {
          props: ['chat'],
          template: '<div data-testid="conversation">{{ chat.id }}</div>',
        },
        CallWorkspace: {
          props: ['accountId', 'callId', 'context'],
          template:
            '<div data-testid="call-workspace">{{ accountId }}:{{ callId }}</div>',
        },
      },
    },
  });

describe('omnichannel inbox', () => {
  it('keeps Voice and the central dialer for an authorized SIP extension when Contact Center is off', async () => {
    store.state.feature = false;
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.find('[data-channel="voice"]').exists()).toBe(true);
    expect(
      wrapper.findAll('[data-channel]')[0].attributes('data-channel')
    ).toBe('voice');
    expect(openEmbeddedSoftphone(1, '1411')).toBe(true);
    await flushPromises();
    expect(wrapper.get('[data-central-voice]').isVisible()).toBe(true);
    expect(wrapper.get('[data-central-dialer] input').element.value).toBe(
      '1411'
    );
    expect(mocks.sip.call).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.calls).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.context).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.agentState).not.toHaveBeenCalled();
  });
  it('does not expose SIP presentation to an Account member without the existing webphone permission', async () => {
    store.state.feature = false;
    store.state.currentUser.accounts[0].permissions = ['contact_manage'];
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.find('[data-channel="voice"]').exists()).toBe(false);
    expect(openEmbeddedSoftphone(1)).toBe(false);
    expect(wrapper.find('[data-inbox-softphone]').exists()).toBe(false);
    expect(JrcContactCenterAPI.context).not.toHaveBeenCalled();
  });
  it('uses the HOYA workspace without enabling Call Center or requesting voice data', async () => {
    store.state.feature = false;
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.find('[data-testid="hoya-inbox-workspace"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="customer-column"]').exists()).toBe(true);
    expect(JrcContactCenterAPI.calls).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.context).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.agentState).not.toHaveBeenCalled();
  });
  beforeEach(() => {
    mocks.sip = Object.fromEntries(
      Object.entries({
        accountId: 1,
        callId: '',
        incoming: false,
        hasCall: false,
        established: false,
        held: false,
        muted: false,
        holdPending: false,
        transferring: false,
        errorMessage: '',
        credential: { extension: '1410' },
        remoteNumber: '',
        duration: '',
        destination: '',
        sessionState: '',
        configured: true,
        registered: true,
        extensionEnabled: true,
        connecting: false,
      }).map(([key, value]) => [key, ref(value)])
    );
    [
      'call',
      'answer',
      'reject',
      'hangup',
      'setMuted',
      'setHold',
      'pressKey',
    ].forEach(key => {
      mocks.sip[key] = vi.fn();
    });
    mocks.route = reactive({ params: { accountId: '1' }, query: {} });
    mocks.router = {
      replace: vi.fn(async target => {
        mocks.route.query = target.query;
        mocks.route.params = target.params;
      }),
      push: vi.fn(),
      resolve: vi.fn(target =>
        webphoneRoutes.find(row => row.name === target.name)
      ),
    };
    store = createStore({
      state: () => ({
        currentUser: {
          id: 5,
          accounts: [
            {
              id: 1,
              role: 'agent',
              custom_role_id: null,
              permissions: ['agent'],
            },
            {
              id: 2,
              role: 'agent',
              custom_role_id: null,
              permissions: ['agent'],
            },
          ],
        },
        feature: true,
        inboxes: [
          { id: 11, channel_type: INBOX_TYPES.WHATSAPP },
          { id: 12, channel_type: INBOX_TYPES.EMAIL },
          { id: 13, channel_type: INBOX_TYPES.INSTAGRAM },
        ],
        conversations: [],
        conversationError: false,
        ended: false,
        conversationPayload: [],
        filters: {},
      }),
      getters: {
        'conversationPage/getHasEndReached': state => () => state.ended,
        getSelectedChat: () => ({}),
        getCurrentUser: state => state.currentUser,
        getCurrentRole: state =>
          state.currentUser.accounts.find(
            a => a.id === Number(mocks.route.params.accountId)
          ).role,
        getCurrentCustomRoleId: state =>
          state.currentUser.accounts.find(
            a => a.id === Number(mocks.route.params.accountId)
          ).custom_role_id,
        'inboxes/getAllInboxes': state => state.inboxes,
        'inboxes/getInboxById': state => id =>
          state.inboxes.find(inbox => inbox.id === id),
        'accounts/isFeatureEnabledonAccount': state => () => state.feature,
        getAllStatusChats: state => () => state.conversations,
        getChatListLoadingStatus: () => false,
        getChatListErrorStatus: state => state.conversationError,
      },
      actions: {
        'inboxes/get': vi.fn(),
        'conversationPage/reset': vi.fn(),
        clearSelectedState: vi.fn(),
        emptyAllConversations: ({ state }) => {
          state.conversations = [];
        },
        updateChatListFilters: ({ state }, filters) => {
          state.filters = filters;
        },
        fetchAllConversations: ({ state }) => {
          state.conversationError = false;
          state.conversations = [...state.conversationPayload];
        },
      },
    });
    JrcContactCenterAPI.calls.mockResolvedValue({ data: { items: [call] } });
    JrcContactCenterAPI.agentState.mockResolvedValue({
      data: { item: { state: 'available' } },
    });
    JrcContactCenterAPI.context.mockResolvedValue({
      data: { capabilities: { operate: true } },
    });
  });

  it.each([false, true])(
    'requires an explicit retry after a conversation error with Contact Center enabled=%s',
    async feature => {
      store.state.feature = feature;
      const dispatch = vi.spyOn(store, 'dispatch');
      const wrapper = mountInbox();
      await flushPromises();
      dispatch.mockClear();
      store.state.conversationError = true;
      await flushPromises();
      expect(wrapper.get('[role="alert"]').text()).toContain(
        'CHAT_LIST.LOAD_ERROR'
      );
      expect(wrapper.text()).not.toContain('Carregar mais atendimentos');
      expect(dispatch).not.toHaveBeenCalledWith('fetchAllConversations');
      const retry = wrapper
        .findAll('button')
        .find(button => button.text() === 'CHAT_LIST.RETRY');
      expect(retry).toBeDefined();
      await retry.trigger('click');
      await flushPromises();
      expect(dispatch).toHaveBeenCalledWith('fetchAllConversations');
      expect(store.state.filters).toEqual(
        expect.objectContaining({ page: 1, assigneeType: 'me' })
      );
      expect(store.state.conversationError).toBe(false);
      expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    }
  );

  it('defaults ordinary agents to mine and rejects an all-assignees URL', async () => {
    mocks.route.query.assignee = 'all';
    const wrapper = mountInbox();
    await flushPromises();
    expect(store.state.filters.assigneeType).toBe('me');
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ME');
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ALL'
    );
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.UNASSIGNED'
    );
    expect(JrcContactCenterAPI.calls).toHaveBeenLastCalledWith(
      1,
      expect.objectContaining({ assignee_type: 'me' })
    );
  });

  it('does not elevate a participating-only custom role', async () => {
    store.state.currentUser.accounts[0].custom_role_id = 4;
    store.state.currentUser.accounts[0].permissions = [
      'jrc_contact_center_view',
      'conversation_participating_manage',
    ];
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.ALL'
    );
  });

  it('refetches authorized filters when the URL changes and when navigating back', async () => {
    store.state.currentUser.accounts[0].role = 'administrator';
    store.state.currentUser.accounts[0].permissions = ['administrator'];
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.INBOX.ASSIGNEE.UNASSIGNED'
    );
    mocks.route.query.assignee = 'all';
    await flushPromises();
    expect(store.state.filters.assigneeType).toBe('all');
    expect(JrcContactCenterAPI.calls).toHaveBeenLastCalledWith(
      1,
      expect.objectContaining({ assignee_type: 'all' })
    );
    mocks.route.query.assignee = 'me';
    await flushPromises();
    expect(JrcContactCenterAPI.calls).toHaveBeenLastCalledWith(
      1,
      expect.objectContaining({ assignee_type: 'me' })
    );
  });

  it('offers configured messaging and social channels alongside voice', async () => {
    store.state.conversationPayload = [
      { id: 101, inbox_id: 11, meta: {} },
      { id: 102, inbox_id: 12, meta: {} },
      { id: 103, inbox_id: 13, meta: {} },
    ];
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.text()).toContain('JRC_CONTACT_CENTER.INBOX.CHANNELS.VOICE');
    expect(wrapper.text()).toContain('WhatsApp');
    expect(wrapper.text()).toContain('E-mail');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.INBOX.CHANNELS.SOCIAL'
    );
    expect(wrapper.text()).toContain(call.ani);
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.INBOX.CHANNEL_FILTER_LABEL"]')
      .setValue('whatsapp');
    await flushPromises();
    expect(
      wrapper.findAll('[data-testid="conversation"]').map(row => row.text())
    ).toEqual(['101']);
    expect(wrapper.text()).not.toContain(call.ani);
    await wrapper
      .get('select[aria-label="JRC_CONTACT_CENTER.INBOX.CHANNEL_FILTER_LABEL"]')
      .setValue('social');
    await flushPromises();
    expect(
      wrapper.findAll('[data-testid="conversation"]').map(row => row.text())
    ).toEqual(['103']);
  });

  it('opens voice in the existing account-scoped inbox route', async () => {
    const wrapper = mountInbox();
    await flushPromises();
    await wrapper
      .findAll('button')
      .find(b => b.text().includes(call.ani))
      .trigger('click');
    expect(mocks.router.push).toHaveBeenCalledWith(
      expect.objectContaining({
        name: 'inbox_view_conversation',
        params: { accountId: '1', type: 'call', id: 7 },
      })
    );
    mocks.route.params.type = 'call';
    mocks.route.params.id = '7';
    await flushPromises();
    expect(wrapper.get('[data-testid="call-workspace"]').text()).toBe('1:7');
    const toggle = wrapper.get(
      'button[aria-label="JRC_CONTACT_CENTER.INBOX_360.TOGGLE_LIST"]'
    );
    await toggle.trigger('click');
    expect(toggle.attributes('aria-expanded')).toBe('true');
    expect(wrapper.get('[data-testid="call-workspace"]').text()).toBe('1:7');
    expect(mocks.route.params.accountId).toBe('1');
    expect(mocks.route.query).toEqual({});
  });

  it('discards voice and conversation view state from the previous account', async () => {
    let resolveOld;
    JrcContactCenterAPI.calls.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.get('[data-testid="conversation-panel"]').text()).toBe('1');
    mocks.route.params.accountId = '2';
    JrcContactCenterAPI.calls.mockResolvedValue({
      data: { items: [{ ...call, id: 8, ani: '+550000000002' }] },
    });
    await flushPromises();
    resolveOld({ data: { items: [call] } });
    await flushPromises();
    expect(wrapper.text()).toContain('+550000000002');
    expect(wrapper.text()).not.toContain(call.ani);
    expect(wrapper.get('[data-testid="conversation-panel"]').text()).toBe('2');
  });

  it('discards an old all-assignees voice response after returning to mine', async () => {
    store.state.currentUser.accounts[0].role = 'administrator';
    store.state.currentUser.accounts[0].permissions = ['administrator'];
    mocks.route.query.assignee = 'all';
    let resolveOld;
    JrcContactCenterAPI.calls.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveOld = resolve;
        })
    );
    const wrapper = mountInbox();
    await flushPromises();
    mocks.route.query.assignee = 'me';
    await flushPromises();
    resolveOld({ data: { items: [{ ...call, ani: 'PEER-CALL' }] } });
    await flushPromises();
    expect(wrapper.text()).toContain(call.ani);
    expect(wrapper.text()).not.toContain('PEER-CALL');
  });

  it('keeps Contact Center records unavailable while allowing the independently authorized SIP presentation', async () => {
    store.state.feature = false;
    const wrapper = mountInbox();
    await flushPromises();
    expect(JrcContactCenterAPI.calls).not.toHaveBeenCalled();
    expect(JrcContactCenterAPI.context).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain(call.ani);
    expect(wrapper.find('[data-channel="voice"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="call-workspace"]').exists()).toBe(false);
  });

  it('clears Contact Center records when its feature is removed without removing authorized SIP presentation', async () => {
    store.state.feature = false;
    const wrapper = mountInbox();
    await flushPromises();
    expect(JrcContactCenterAPI.calls).not.toHaveBeenCalled();

    store.state.feature = true;
    await flushPromises();
    expect(JrcContactCenterAPI.calls).toHaveBeenCalledWith(1, {
      limit: 50,
      assignee_type: 'me',
    });
    expect(wrapper.text()).toContain(call.ani);

    store.state.feature = false;
    await flushPromises();
    expect(wrapper.text()).not.toContain(call.ani);
    expect(wrapper.find('[data-channel="voice"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="call-workspace"]').exists()).toBe(false);
  });

  it('shows an error instead of an endless voice workspace spinner', async () => {
    mocks.route.params = { accountId: '1', type: 'call', id: '7' };
    mocks.route.query.channel = 'voice';
    JrcContactCenterAPI.calls.mockRejectedValueOnce(new Error('denied'));
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.find('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
    expect(wrapper.find('[data-testid="loading"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="call-workspace"]').exists()).toBe(false);
  });

  it('renders the three regions, collapsible channel groups and the seven contextual tabs', async () => {
    const wrapper = mountInbox();
    await flushPromises();
    ['inbox-list', 'interaction-workspace', 'customer-column'].forEach(
      region => {
        expect(wrapper.find(`[data-testid="${region}"]`).exists()).toBe(true);
      }
    );
    const voiceGroup = wrapper.get('[data-channel="voice"] > button');
    await voiceGroup.trigger('click');
    expect(voiceGroup.attributes('aria-expanded')).toBe('false');
    expect(
      wrapper.get('[data-channel="voice"] > div').element.style.display
    ).toBe('none');
    await voiceGroup.trigger('click');
    expect(
      wrapper.get('[data-channel="voice"] > div').element.style.display
    ).toBe('');
    expect(wrapper.text()).toContain(call.ani);
    const tabs = wrapper
      .get('nav[aria-label="JRC_CONTACT_CENTER.INBOX_360.WORKSPACE_TABS"]')
      .findAll('button');
    expect(tabs).toHaveLength(7);
    await tabs[3].trigger('click');
    expect(tabs[3].attributes('aria-pressed')).toBe('true');
    expect(wrapper.text()).toContain(
      'JRC_CONTACT_CENTER.INBOX_360.ORDERS_EMPTY'
    );
  });

  it('waits for list bootstrap before mounting a directly linked conversation', async () => {
    mocks.route.params = { accountId: '1', type: 'conversation', id: '101' };
    let resolveList;
    const dispatch = store.dispatch.bind(store);
    vi.spyOn(store, 'dispatch').mockImplementation((type, ...args) =>
      type === 'fetchAllConversations'
        ? new Promise(resolve => {
            resolveList = resolve;
          })
        : dispatch(type, ...args)
    );
    const wrapper = mountInbox();
    await flushPromises();
    expect(wrapper.find('[data-testid="conversation-panel"]').exists()).toBe(
      false
    );
    expect(store.state.filters.assigneeType).toBe('me');
    resolveList();
    await flushPromises();
    expect(wrapper.get('[data-testid="conversation-panel"]').text()).toBe('1');
  });

  it('opens a messaging conversation without dropping the authorized account or filter', async () => {
    store.state.conversationPayload = [{ id: 101, inbox_id: 11, meta: {} }];
    const wrapper = mountInbox();
    await flushPromises();
    await wrapper.get('[data-testid="conversation"]').trigger('click');
    expect(mocks.router.push).toHaveBeenCalledWith({
      name: 'inbox_view_conversation',
      params: { accountId: '1', type: 'conversation', id: 101 },
      query: mocks.route.query,
    });
  });
});
