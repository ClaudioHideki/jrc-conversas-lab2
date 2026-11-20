import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { createStore } from 'vuex';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { useSipWebphone } from 'dashboard/routes/dashboard/webphone/useSipWebphone';
import CCAPI from 'dashboard/api/jrcContactCenter';
import HoyaInboxWorkspace from './HoyaInboxWorkspace.vue';
import { openEmbeddedSoftphone } from '../webphone/useEmbeddedSoftphone';
import { CONVERSATION_TOOLS } from './conversationTools';
import { GLOBAL_VOICE_SHELL } from '../webphone/voiceShell';
const pagination = vi.hoisted(() => ({ observe: null }));
vi.mock('@vueuse/core', async importOriginal => ({
  ...(await importOriginal()),
  useIntersectionObserver: vi.fn((target, callback) => {
    pagination.observe = callback;
    return { stop: vi.fn() };
  }),
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => ({ hasActiveCall: false, hasIncomingCall: false }),
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({ isInitiating: ref(false) }),
}));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ query: {} }),
  onBeforeRouteLeave: vi.fn(),
  onBeforeRouteUpdate: vi.fn(),
}));
vi.mock('dashboard/routes/dashboard/webphone/useSipWebphone', () => ({
  useSipWebphone: vi.fn(),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    agentState: vi.fn(),
    qualifications: vi.fn(),
    startQualification: vi.fn(),
    saveQualificationDraft: vi.fn(),
    completeQualification: vi.fn(),
  },
}));
enableAutoUnmount(afterEach);
let sip;
const pendingResponse = {
  data: {
    items: [
      {
        id: 11,
        account_id: 1,
        account_user_id: 9,
        channel: 'voice',
        call_session_id: 7,
        started_at: new Date().toISOString(),
        completed_at: null,
        acw_limit_seconds: 40,
      },
    ],
    agent: { account_user_id: 9, pending_qualifications: [] },
    policy: { limits: { voice: 40, whatsapp: 50 } },
  },
};
const props = {
  accountId: 1,
  softphoneAccess: true,
  currentCallId: 7,
  calls: [{ id: 7, ani: 'LOCAL-7', status: 'connected' }],
  inboxFor: () => ({}),
  context: {
    capabilities: { operate: true },
    provider: {
      capabilities: {
        sip_webrtc: 'available',
        hold: 'available',
        transfer_blind: 'available',
      },
    },
  },
};
const workspaceUser = ref({
  id: 9,
  accounts: [{ id: 1, role: 'agent', permissions: [] }],
});
beforeEach(() => {
  workspaceUser.value = {
    id: 9,
    accounts: [{ id: 1, role: 'agent', permissions: [] }],
  };
});
const store = createStore({
  getters: {
    getSelectedChat: () => ({}),
    getCurrentUser: () => workspaceUser.value,
    'accounts/isFeatureEnabledonAccount': () => () => false,
  },
});

const scopedConversation = ref({
  id: 21,
  account_id: 1,
  inbox_id: 3,
  status: 'open',
  meta: { sender: {} },
});
const scopedUser = ref(9);
const scopedStore = createStore({
  getters: {
    getSelectedChat: () => scopedConversation.value,
    getCurrentUserID: () => scopedUser.value,
    'accounts/isFeatureEnabledonAccount': () => (_, flag) => flag === 'macros',
  },
});
const global = {
  plugins: [store],
  stubs: {
    Dialog: { methods: { open() {}, close() {} }, template: '<div />' },
    RouterLink: { template: '<a><slot /></a>' },
    RouterView: true,
    CallWorkspace: { name: 'CallWorkspace', template: '<div />' },
  },
};
describe('inbox native SIP action guards', () => {
  it('offers voice configuration inside Attendance only to a backend-authorized configurator', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    expect(wrapper.find('[data-voice-settings]').exists()).toBe(false);
    await wrapper.setProps({
      context: {
        ...props.context,
        capabilities: { operate: true, configure: true },
      },
    });
    expect(wrapper.find('[data-voice-settings]').exists()).toBe(true);
    await wrapper.setProps({
      context: {
        ...props.context,
        capabilities: { operate: true, configure: false },
      },
    });
    expect(wrapper.find('[data-voice-settings]').exists()).toBe(false);
  });
  it('keeps a unique telephone candidate outside the customer 360 identity and displays the source warning', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    wrapper.findComponent({ name: 'CallWorkspace' }).vm.$emit('loaded', {
      call: { id: 7, contact_id: null, status: 'connected' },
      customer: {
        status: 'identified',
        identity_source: 'phone_candidates',
        contacts: [{ id: 77, name: 'SYNTHETIC candidate' }],
        ambiguous: false,
      },
    });
    await flushPromises();
    expect(wrapper.vm.identity.contactId).toBeNull();
    expect(wrapper.get('[data-hoya-phone-candidate]').text()).toBe(
      'JRC_CONTACT_CENTER.CALL.PHONE_CANDIDATE'
    );
    expect(
      wrapper
        .get('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.OVERVIEW"]')
        .attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-open-linked-master]').exists()).toBe(false);
  });

  it('uses the explicit call contact for customer 360 and clears that identity when the next call is unlinked', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    const native = wrapper.findComponent({ name: 'CallWorkspace' });
    native.vm.$emit('loaded', {
      call: { id: 7, contact_id: 77, status: 'connected' },
      customer: {
        status: 'identified',
        identity_source: 'call_contact_link',
        contacts: [{ id: 77 }],
        ambiguous: false,
      },
    });
    await flushPromises();
    expect(wrapper.vm.identity.contactId).toBe(77);
    expect(wrapper.find('[data-hoya-phone-candidate]').exists()).toBe(false);
    expect(
      wrapper
        .get('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.OVERVIEW"]')
        .attributes('disabled')
    ).toBeUndefined();
    await wrapper.setProps({ currentCallId: 8 });
    await flushPromises();
    expect(wrapper.vm.identity.contactId).toBeNull();
    expect(
      wrapper
        .get('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.OVERVIEW"]')
        .attributes('disabled')
    ).toBeDefined();
  });

  it('loads the next page at the end of the existing mixed channel list without changing the selected interaction', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: { ...props, canLoadMore: true },
      global,
    });
    await flushPromises();
    expect(wrapper.find('[data-conversation-scroll]').exists()).toBe(true);
    pagination.observe([{ isIntersecting: true }]);
    await flushPromises();
    expect(wrapper.emitted('loadMore')).toEqual([[]]);
    expect(wrapper.emitted('selectCall')).toBeUndefined();
    expect(wrapper.emitted('channelChange')).toBeUndefined();
    await wrapper.setProps({ loading: true });
    pagination.observe([{ isIntersecting: false }]);
    pagination.observe([{ isIntersecting: true }]);
    await flushPromises();
    expect(wrapper.emitted('loadMore')).toHaveLength(1);
    await wrapper.setProps({ loading: false, conversationError: true });
    expect(wrapper.emitted('loadMore')).toHaveLength(1);
    await wrapper.setProps({ conversationError: false, canLoadMore: false });
    expect(wrapper.emitted('loadMore')).toHaveLength(1);
  });

  it('composes the five Voice V4 tabs and keeps script and notes in the call without duplicate SIP controls', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        inboxFor: () => ({ channel_type: 'Channel::Whatsapp' }),
      },
      global: { ...global, provide: { [GLOBAL_VOICE_SHELL]: true } },
    });
    await flushPromises();
    const tabs = wrapper.get(
      'nav[aria-label="JRC_CONTACT_CENTER.INBOX_360.WORKSPACE_TABS"]'
    );
    expect(tabs.findAll('button')).toHaveLength(5);
    expect(tabs.text()).toContain('VOICE_V4.CALL_TAB');
    expect(tabs.text()).toContain('VOICE_V4.MORE');
    expect(wrapper.get('[data-voice-script]').text()).toContain(
      'JRC_CONTACT_CENTER.INBOX_360.SCRIPT'
    );
    expect(
      wrapper.find('[data-central-voice] [data-voice-controls]').exists()
    ).toBe(false);
    expect(
      wrapper
        .find('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.HANGUP"]')
        .exists()
    ).toBe(false);
  });
  it('opens the authorized SIP session centrally without requesting Contact Center state', async () => {
    CCAPI.agentState.mockClear();
    const wrapper = mount(HoyaInboxWorkspace, {
      props: { ...props, context: null, currentCallId: null },
      global,
    });
    await flushPromises();
    expect(CCAPI.agentState).not.toHaveBeenCalled();
    expect(wrapper.find('[data-testid="hoya-inbox-workspace"]').exists()).toBe(
      true
    );
    expect(openEmbeddedSoftphone(1)).toBe(true);
    await flushPromises();
    expect(wrapper.get('[data-central-voice]').isVisible()).toBe(true);
    await wrapper.get('[data-voice-action="MUTE"]').trigger('click');
    expect(sip.setMuted).toHaveBeenCalledWith(true);
    expect(CCAPI.qualifications).not.toHaveBeenCalled();
    expect(sip.initialize).not.toHaveBeenCalled();
    expect(sip.connect).not.toHaveBeenCalled();
  });
  it('does not operate a selected native record when its Contact Center permission is denied', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        context: { ...props.context, capabilities: { operate: false } },
      },
      global,
    });
    await flushPromises();
    wrapper.findComponent({ name: 'CallWorkspace' }).vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    const mute = wrapper.get('[data-voice-action="MUTE"]');
    expect(mute.attributes('disabled')).toBeDefined();
    await mute.trigger('click');
    expect(sip.setMuted).not.toHaveBeenCalled();
  });
  it('reports a conversation load failure and emits an explicit retry without operating SIP', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        currentCallId: null,
        calls: [],
        conversationError: true,
      },
      global,
    });
    await flushPromises();
    const alert = wrapper.get('[role="alert"]');
    expect(alert.text()).toContain('CHAT_LIST.LOAD_ERROR');
    await alert.get('button').trigger('click');
    expect(wrapper.emitted('retryConversations')).toEqual([[]]);
    expect(sip.initialize).not.toHaveBeenCalled();
    expect(sip.connect).not.toHaveBeenCalled();
    expect(sip.answer).not.toHaveBeenCalled();
  });

  it('does not invent a ringing state or elapsed time for an unknown call', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: { ...props, currentCallId: 99, calls: [] },
      global,
    });
    await flushPromises();
    const header = wrapper
      .get('[data-testid="interaction-workspace"]')
      .get('header');
    expect(header.text()).toContain('JRC_CONTACT_CENTER.INBOX.TITLE');
    expect(header.text()).not.toContain(
      'JRC_CONTACT_CENTER.INBOX_360.CALL_STATES.ringing'
    );
    expect(header.text()).not.toContain('00:00:00');
  });
  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
    scopedUser.value = 9;
    scopedConversation.value = {
      id: 21,
      account_id: 1,
      inbox_id: 3,
      status: 'open',
      meta: { sender: {} },
    };
    sip = {
      accountId: ref(1),
      callId: ref('native-7'),
      incoming: ref(false),
      hasCall: ref(true),
      established: ref(true),
      held: ref(false),
      muted: ref(false),
      holdPending: ref(false),
      errorMessage: ref(''),
      credential: ref({ extension: '1410' }),
      configured: ref(true),
      registered: ref(true),
      connecting: ref(false),
      extensionEnabled: ref(true),
      remoteNumber: ref('1410'),
      duration: ref('03:27'),
      destination: ref(''),
      sessionState: ref('Established'),
      answer: vi.fn(),
      hangup: vi.fn(),
      reject: vi.fn(),
      setMuted: vi.fn(),
      setHold: vi.fn(),
      initialize: vi.fn(),
      connect: vi.fn(),
    };
    useSipWebphone.mockReturnValue(sip);
    CCAPI.qualifications.mockResolvedValue({
      data: {
        items: [],
        agent: { account_user_id: 9, pending_qualifications: [] },
        policy: { limits: { voice: 40, whatsapp: 50 } },
      },
    });
    CCAPI.agentState.mockResolvedValue({
      data: { item: { state: 'available' } },
    });
  });

  it('places the native tools after Tasks and passes only the selected Account conversation to them', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        context: null,
        currentCallId: null,
        currentConversationId: 21,
        conversations: [scopedConversation.value],
      },
      global: {
        ...global,
        plugins: [scopedStore],
        stubs: { ...global.stubs, InboxConversationTools: true },
      },
    });
    await flushPromises();
    const buttons = wrapper.get('nav').findAll('button');
    const taskIndex = buttons.findIndex(
      button =>
        button.attributes('aria-label') === 'JRC_CONTACT_CENTER.INBOX_360.TASKS'
    );
    expect(
      buttons
        .slice(taskIndex + 1)
        .map(button => button.attributes('data-conversation-tool'))
    ).toEqual(CONVERSATION_TOOLS.map(item => item.key));
    await CONVERSATION_TOOLS.reduce(async (previous, tool) => {
      await previous;
      await wrapper
        .get(`[data-conversation-tool="${tool.key}"]`)
        .trigger('click');
      expect(
        wrapper.getComponent({ name: 'InboxConversationTools' }).props()
      ).toMatchObject({ accountId: 1, conversationId: 21, tool: tool.key });
    }, Promise.resolve());
    expect(wrapper.findComponent({ name: 'RouterView' }).exists()).toBe(true);
    expect(sip.initialize).not.toHaveBeenCalled();
    await wrapper.setProps({ accountId: 2 });
    await flushPromises();
    expect(
      wrapper.findComponent({ name: 'InboxConversationTools' }).exists()
    ).toBe(false);
    expect(
      wrapper
        .get('[data-conversation-tool="contact_notes"]')
        .attributes('disabled')
    ).toBeDefined();
  });

  it('keeps conversation tools unavailable for a voice call or an empty selection', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    wrapper.findAll('[data-conversation-tool]').forEach(button => {
      expect(button.attributes('disabled')).toBeDefined();
    });
    await wrapper.setProps({ currentCallId: null });
    await flushPromises();
    wrapper.findAll('[data-conversation-tool]').forEach(button => {
      expect(button.attributes('disabled')).toBeDefined();
    });
  });

  it('resizes with pointer and keyboard, clamps the width and isolates the saved preference by user', async () => {
    const originalWidth = window.innerWidth;
    window.innerWidth = 1920;
    const wrapper = mount(HoyaInboxWorkspace, {
      props: { ...props, context: null, currentCallId: null },
      global: { ...global, plugins: [scopedStore] },
    });
    await flushPromises();
    const separator = wrapper.get('[data-testid="attendance-list-resizer"]');
    expect(separator.attributes('aria-valuenow')).toBe('240');
    separator.element.dispatchEvent(
      new MouseEvent('pointerdown', { bubbles: true, clientX: 300, button: 0 })
    );
    separator.element.dispatchEvent(
      new MouseEvent('pointermove', { bubbles: true, clientX: 396 })
    );
    separator.element.dispatchEvent(
      new MouseEvent('pointerup', { bubbles: true })
    );
    await flushPromises();
    expect(separator.attributes('aria-valuenow')).toBe('336');
    expect(localStorage.getItem('jrc:attendance-list-width:1:9')).toBe('336');
    await separator.trigger('keydown', { key: 'End' });
    expect(separator.attributes('aria-valuenow')).toBe('480');
    await separator.trigger('keydown', { key: 'ArrowRight' });
    expect(separator.attributes('aria-valuenow')).toBe('480');
    await separator.trigger('keydown', { key: 'Home' });
    expect(separator.attributes('aria-valuenow')).toBe('192');
    await separator.trigger('keydown', { key: 'ArrowRight' });
    expect(separator.attributes('aria-valuenow')).toBe('208');
    scopedUser.value = 10;
    await flushPromises();
    expect(separator.attributes('aria-valuenow')).toBe('240');
    scopedUser.value = 9;
    await flushPromises();
    expect(separator.attributes('aria-valuenow')).toBe('208');
    await separator.trigger('dblclick');
    expect(separator.attributes('aria-valuenow')).toBe('240');
    expect(localStorage.getItem('jrc:attendance-list-width:1:9')).toBeNull();
    wrapper.unmount();
    window.innerWidth = originalWidth;
  });
  it('never initializes another phone and enables controls only for the matching native call', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    const mute = wrapper.get('button[data-voice-action="MUTE"]');
    expect(mute.attributes('disabled')).toBeDefined();
    const nativeWorkspace = wrapper.findComponent({ name: 'CallWorkspace' });
    nativeWorkspace.vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    expect(mute.attributes('disabled')).toBeUndefined();
    await mute.trigger('click');
    expect(sip.setMuted).toHaveBeenCalledWith(true);
    expect(sip.initialize).not.toHaveBeenCalled();
    expect(sip.connect).not.toHaveBeenCalled();
  });
  it('keeps SIP controls disabled for a different Account or call identifier', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    const nativeWorkspace = wrapper.findComponent({ name: 'CallWorkspace' });
    nativeWorkspace.vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-8', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    const mute = wrapper.get('button[data-voice-action="MUTE"]');
    expect(mute.attributes('disabled')).toBeDefined();
    sip.callId.value = 'native-8';
    sip.accountId.value = 2;
    await flushPromises();
    expect(mute.attributes('disabled')).toBeDefined();
    await mute.trigger('click');
    expect(sip.setMuted).not.toHaveBeenCalled();
  });
  it('does not enable provider actions with unavailable capabilities', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        context: {
          capabilities: { operate: true },
          provider: { capabilities: {} },
        },
      },
      global,
    });
    await flushPromises();
    const nativeWorkspace = wrapper.findComponent({ name: 'CallWorkspace' });
    nativeWorkspace.vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    ['MUTE', 'HOLD', 'TRANSFER'].forEach(key => {
      expect(
        wrapper.get(`button[data-voice-action="${key}"]`).attributes('disabled')
      ).toBeDefined();
    });
    expect(sip.setHold).not.toHaveBeenCalled();
  });
  it('reports native SIP failure without displaying a false success', async () => {
    sip.setHold.mockRejectedValue(new Error('native failure'));
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    const nativeWorkspace = wrapper.findComponent({ name: 'CallWorkspace' });
    nativeWorkspace.vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    await wrapper.get('button[data-voice-action="HOLD"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'JRC_CONTACT_CENTER.COMMON.ERROR'
    );
  });
  it('displays a failure stored by the native phone even when its method handles the rejection', async () => {
    sip.setHold.mockImplementation(async () => {
      sip.errorMessage.value = 'Native phone could not hold';
    });
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    const nativeWorkspace = wrapper.findComponent({ name: 'CallWorkspace' });
    nativeWorkspace.vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    await wrapper.get('button[data-voice-action="HOLD"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').text()).toBe(
      'Native phone could not hold'
    );
  });

  it('requires ACW after the native hangup control and terminal confirmation', async () => {
    sip.hangup.mockImplementation(async () => {
      CCAPI.qualifications.mockResolvedValue(pendingResponse);
      sip.hasCall.value = false;
      sip.established.value = false;
    });
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    wrapper.findComponent({ name: 'CallWorkspace' }).vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(false);
    await wrapper
      .get('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.HANGUP"]')
      .trigger('click');
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(true);
  });
  it('requires ACW when a voice call ends remotely', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    const native = wrapper.findComponent({ name: 'CallWorkspace' });
    native.vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'connected' },
      customer: { contacts: [] },
    });
    await flushPromises();
    CCAPI.qualifications.mockResolvedValue(pendingResponse);
    sip.hasCall.value = false;
    sip.established.value = false;
    native.vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'ended' },
      customer: { contacts: [] },
    });
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(true);
  });
  it('preserves pending qualification when another incoming SIP call arrives and still permits rejection', async () => {
    CCAPI.qualifications.mockResolvedValue(pendingResponse);
    sip.incoming.value = true;
    sip.callId.value = 'native-new';
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(true);
    const incoming = wrapper.get('[data-pending-incoming]');
    expect(incoming.text()).toContain('SOFTPHONE.INBOX.QUALIFICATION_PENDING');
    await incoming.get('button').trigger('click');
    expect(sip.reject).toHaveBeenCalledOnce();
    expect(sip.answer).not.toHaveBeenCalled();
    expect(wrapper.find('progress').exists()).toBe(true);
  });
  it('saves an incomplete draft from the reused Hoya controls without completion or a SIP operation', async () => {
    const pending = {
      ...pendingResponse.data.items[0],
      draft_revision: 'native-manual-revision',
    };
    CCAPI.qualifications.mockResolvedValue({
      data: { ...pendingResponse.data, items: [pending] },
    });
    const saved = {
      ...pending,
      reason_code: 'order',
      notes: 'SYNTHETIC Hoya draft',
      outcome_code: '',
      draft_revision: 'new-manual-revision',
    };
    CCAPI.saveQualificationDraft.mockResolvedValue({
      data: { item: saved, agent: pendingResponse.data.agent },
    });
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    await wrapper.get('[data-qualification-field="reason"]').setValue('order');
    await wrapper
      .get('[data-qualification-field="note"]')
      .setValue('SYNTHETIC Hoya draft');
    await wrapper.get('[data-save-qualification-draft]').trigger('click');
    await flushPromises();
    expect(CCAPI.saveQualificationDraft).toHaveBeenCalledWith(
      1,
      11,
      { reason_code: 'order', outcome_code: '', notes: 'SYNTHETIC Hoya draft' },
      'native-manual-revision'
    );
    expect(wrapper.get('[data-qualification-field="note"]').element.value).toBe(
      'SYNTHETIC Hoya draft'
    );
    expect(wrapper.get('[data-complete-qualification]').element.disabled).toBe(
      true
    );
    expect(wrapper.find('progress').exists()).toBe(true);
    expect(CCAPI.completeQualification).not.toHaveBeenCalled();
    expect(sip.hangup).not.toHaveBeenCalled();
    expect(sip.answer).not.toHaveBeenCalled();
  });

  it('keeps the Hoya draft form read-only when the actual workspace context lacks operating authority', async () => {
    const pending = {
      ...pendingResponse.data.items[0],
      draft_revision: 'native-read-only-revision',
      notes: 'SYNTHETIC readable own draft',
    };
    CCAPI.qualifications.mockResolvedValue({
      data: { ...pendingResponse.data, items: [pending] },
    });
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        context: { ...props.context, capabilities: { operate: false } },
      },
      global,
    });
    await flushPromises();
    const form = wrapper.get('[data-pending-qualification-form]');
    expect(form.get('[data-qualification-field="note"]').element.value).toBe(
      'SYNTHETIC readable own draft'
    );
    expect(
      form
        .findAll('select, textarea, button')
        .every(control => control.element.disabled)
    ).toBe(true);
    await form.get('[data-save-qualification-draft]').trigger('click');
    expect(CCAPI.saveQualificationDraft).not.toHaveBeenCalled();
    expect(CCAPI.completeQualification).not.toHaveBeenCalled();
  });

  it.each([false, true])(
    'matches the deadline bar to the actual overdue state=%s without changing the clock or applied limit',
    async overdue => {
      const pending = {
        ...pendingResponse.data.items[0],
        started_at: new Date(
          Date.now() - (overdue ? 90000 : 1000)
        ).toISOString(),
        overdue,
      };
      CCAPI.qualifications.mockResolvedValue({
        data: { ...pendingResponse.data, items: [pending] },
      });
      const wrapper = mount(HoyaInboxWorkspace, { props, global });
      await flushPromises();
      const progress = wrapper.get('[data-acw-deadline-progress]');
      expect(progress.classes()).toContain(
        overdue ? 'accent-n-ruby-9' : 'accent-n-blue-9'
      );
      expect(Number(progress.attributes('max'))).toBe(40);
      if (overdue) expect(Number(progress.attributes('value'))).toBe(40);
      else {
        expect(Number(progress.attributes('value'))).toBeGreaterThanOrEqual(1);
        expect(Number(progress.attributes('value'))).toBeLessThan(40);
      }
      expect(CCAPI.completeQualification).not.toHaveBeenCalled();
      expect(sip.answer).not.toHaveBeenCalled();
    }
  );

  it('restores required tabulation when reopening an ended voice interaction', async () => {
    CCAPI.qualifications.mockResolvedValue(pendingResponse);
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    wrapper.findComponent({ name: 'CallWorkspace' }).vm.$emit('loaded', {
      call: { id: 7, external_session_id: 'native-7', status: 'ended' },
      customer: { contacts: [] },
    });
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(true);
  });
  it.each([
    'Channel::Email',
    'Channel::Instagram',
    'Channel::Facebook',
    'Channel::Api',
  ])('does not show Encerramento for %s', async channelType => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        currentCallId: null,
        currentConversationId: 21,
        conversations: [{ id: 21, inbox_id: 1 }],
        inboxFor: () => ({ channel_type: channelType }),
      },
      global,
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.INBOX_360.CLOSING'
    );
  });
  it.each([
    { channel_type: 'Channel::Whatsapp' },
    { channel_type: 'Channel::TwilioSms', medium: 'whatsapp' },
  ])(
    'places Encerramento after Tasks in supported WhatsApp transport',
    async inbox => {
      const wrapper = mount(HoyaInboxWorkspace, {
        props: {
          ...props,
          currentCallId: null,
          currentConversationId: 21,
          conversations: [{ id: 21, inbox_id: 1 }],
          inboxFor: () => inbox,
        },
        global,
      });
      await flushPromises();
      const text = wrapper
        .get('nav[aria-label="JRC_CONTACT_CENTER.INBOX_360.WORKSPACE_TABS"]')
        .text();
      expect(
        text.indexOf('JRC_CONTACT_CENTER.INBOX_360.CLOSING')
      ).toBeGreaterThan(text.indexOf('JRC_CONTACT_CENTER.INBOX_360.TASKS'));
    }
  );
  it('keeps API bridges outside required tabulation even when their presentation is WhatsApp', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: {
        ...props,
        currentCallId: null,
        currentConversationId: 21,
        conversations: [{ id: 21, inbox_id: 1 }],
        inboxFor: () => ({
          channel_type: 'Channel::Api',
          name: 'WhatsApp bridge',
          additional_attributes: { provider: 'evolution' },
        }),
      },
      global,
    });
    await flushPromises();
    expect(wrapper.text()).not.toContain(
      'JRC_CONTACT_CENTER.INBOX_360.CLOSING'
    );
  });

  it('does not restore private tabulation from an old actor in the same account', async () => {
    let resolve;
    CCAPI.qualifications.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    workspaceUser.value = {
      id: 10,
      accounts: [{ id: 1, role: 'agent', custom_role_id: 44 }],
    };
    await flushPromises();
    resolve(pendingResponse);
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(false);
    expect(CCAPI.qualifications).toHaveBeenCalledTimes(2);
  });
  it('clears the tabulation when the same account membership changes while the new read is pending', async () => {
    CCAPI.qualifications.mockResolvedValueOnce(pendingResponse);
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(true);
    let resolve;
    CCAPI.qualifications.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    workspaceUser.value = {
      id: 9,
      accounts: [{ id: 1, role: 'agent', permissions: ['restricted'] }],
    };
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(false);
    resolve({ data: { ...pendingResponse.data, items: [] } });
    await flushPromises();
    expect(wrapper.find('progress').exists()).toBe(false);
  });
  it('does not discard current tabulation on a native presence-only refresh', async () => {
    CCAPI.qualifications.mockResolvedValue(pendingResponse);
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    CCAPI.qualifications.mockClear();
    workspaceUser.value.accounts[0].availability = 'busy';
    workspaceUser.value.accounts[0].active_at = 99;
    await flushPromises();
    expect(CCAPI.qualifications).not.toHaveBeenCalled();
    expect(wrapper.find('progress').exists()).toBe(true);
  });

  it('discards the independent operator fallback if its read arrives after qualification authorization is denied', async () => {
    let resolve;
    CCAPI.agentState.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    CCAPI.qualifications.mockRejectedValueOnce({ response: { status: 403 } });
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    resolve({
      data: {
        item: {
          account_user_id: 9,
          state: 'paused',
          pause_catalog: {
            enabled: true,
            reasons: [{ code: 'PRIVATE old source' }],
          },
        },
      },
    });
    await flushPromises();
    expect(wrapper.vm.agent).toBeNull();
    expect(wrapper.vm.displayAgent).toBeNull();
    expect(wrapper.find('progress').exists()).toBe(false);
    expect(wrapper.text()).not.toContain('PRIVATE old source');
  });
});
