import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { createStore } from 'vuex';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { useSipWebphone } from 'dashboard/routes/dashboard/webphone/useSipWebphone';
import CCAPI from 'dashboard/api/jrcContactCenter';
import HoyaInboxWorkspace from './HoyaInboxWorkspace.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', async importOriginal => ({
  ...(await importOriginal()),
  useRoute: () => ({ query: {} }),
}));
vi.mock('dashboard/routes/dashboard/webphone/useSipWebphone', () => ({
  useSipWebphone: vi.fn(),
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    agentState: vi.fn(),
    qualifications: vi.fn(),
    startQualification: vi.fn(),
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
const store = createStore({
  getters: {
    getSelectedChat: () => ({}),
    'accounts/isFeatureEnabledonAccount': () => () => false,
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
  it('does not invent a ringing state or elapsed time for an unknown call', async () => {
    const wrapper = mount(HoyaInboxWorkspace, {
      props: { ...props, currentCallId: 99, calls: [] },
      global,
    });
    await flushPromises();
    const header = wrapper
      .get('[data-testid="interaction-workspace"]')
      .get('header');
    expect(header.text()).toContain('#99');
    expect(header.text()).not.toContain(
      'JRC_CONTACT_CENTER.INBOX_360.CALL_STATES.ringing'
    );
    expect(header.text()).not.toContain('00:00:00');
  });
  beforeEach(() => {
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
      answer: vi.fn(),
      hangup: vi.fn(),
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
  it('never initializes another phone and enables controls only for the matching native call', async () => {
    const wrapper = mount(HoyaInboxWorkspace, { props, global });
    await flushPromises();
    const mute = wrapper.get(
      'button[aria-label="JRC_CONTACT_CENTER.INBOX_360.MUTE"]'
    );
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
    const mute = wrapper.get(
      'button[aria-label="JRC_CONTACT_CENTER.INBOX_360.MUTE"]'
    );
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
    ['ANSWER', 'HANGUP', 'MUTE', 'HOLD', 'TRANSFER'].forEach(key => {
      expect(
        wrapper
          .get(`button[aria-label="JRC_CONTACT_CENTER.INBOX_360.${key}"]`)
          .attributes('disabled')
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
    await wrapper
      .get('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.HOLD"]')
      .trigger('click');
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
    await wrapper
      .get('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.HOLD"]')
      .trigger('click');
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
});
