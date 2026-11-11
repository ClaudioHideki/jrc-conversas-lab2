import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import GlobalVoiceBar from '../GlobalVoiceBar.vue';

const state = vi.hoisted(() => ({
  sip: null,
  account: null,
  user: null,
  allowed: true,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('../useQuickActionAccess', () => ({
  useQuickActionContext: () => ({
    accountId: state.account,
    userId: state.user,
    routeAllowed: () => state.allowed,
    policy: { isFeatureFlagEnabled: () => false },
  }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }));
vi.mock('dashboard/routes/dashboard/webphone/useSipWebphone', () => ({
  useSipWebphone: () => state.sip,
}));

const options = {
  global: {
    stubs: {
      InboxVoicePanel: {
        name: 'InboxVoicePanel',
        props: {
          accountId: Number,
          controlsOnly: Boolean,
          nativeCallId: Number,
        },
        template: '<div data-active-voice-controls />',
      },
      Dialog: {
        methods: { open() {}, close() {} },
        template: '<div><slot /></div>',
      },
    },
  },
};

beforeEach(() => {
  state.allowed = true;
  state.account = ref(7);
  state.user = ref(91);
  state.sip = Object.fromEntries(
    Object.entries({
      accountId: 7,
      hasCall: false,
      callId: 'session-a',
      incoming: false,
      established: false,
      held: false,
      duration: '03:27',
      remoteNumber: 'synthetic-party-a',
      credential: { extension: '1234' },
      registered: true,
      errorMessage: '',
    }).map(([k, v]) => [k, ref(v)])
  );
});

describe('persistent global voice bar', () => {
  it('keeps a rejected call diagnostic visible after SIP termination and hides it after switching Accounts', async () => {
    state.sip.errorMessage.value = 'O PABX recusou a chamada (403).';
    const wrapper = mount(GlobalVoiceBar, options);
    expect(wrapper.get('[role="alert"]').text()).toContain('(403)');
    expect(wrapper.find('[data-active-voice-controls]').exists()).toBe(false);
    state.account.value = 8;
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(false);
    wrapper.unmount();
  });
  it('has an idle state without a fake timer or enabled call controls', () => {
    const wrapper = mount(GlobalVoiceBar, options);
    expect(wrapper.text()).toContain('VOICE_V4.NO_ACTIVE_CALL');
    expect(wrapper.text()).not.toContain('03:27');
    expect(wrapper.find('[data-active-voice-controls]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('keeps the active SIP party instead of a selected WhatsApp customer', async () => {
    state.sip.hasCall.value = true;
    state.sip.established.value = true;
    const wrapper = mount(GlobalVoiceBar, options);
    await flushPromises();
    expect(wrapper.text()).toContain('synthetic-party-a');
    expect(wrapper.text()).toContain('03:27');
    expect(
      wrapper.findComponent({ name: 'InboxVoicePanel' }).props('controlsOnly')
    ).toBe(true);
    expect(
      wrapper.findComponent({ name: 'InboxVoicePanel' }).props('nativeCallId')
    ).toBeUndefined();
    await wrapper.setProps({
      selectedConversationId: 123,
      selectedCustomerName: 'party-b',
    });
    expect(wrapper.text()).toContain('synthetic-party-a');
    expect(wrapper.text()).not.toContain('party-b');
    wrapper.unmount();
  });

  it('never exposes or controls the previous Account session after an account switch', async () => {
    state.sip.hasCall.value = true;
    const wrapper = mount(GlobalVoiceBar, options);
    state.account.value = 8;
    await flushPromises();
    expect(wrapper.text()).not.toContain('synthetic-party-a');
    expect(wrapper.find('[data-active-voice-controls]').exists()).toBe(false);
    wrapper.unmount();
  });
});
