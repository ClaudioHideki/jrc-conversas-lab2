import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import OutboundVoiceDialog from '../OutboundVoiceDialog.vue';
const state = vi.hoisted(() => ({ sip: null }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/routes/dashboard/webphone/useSipWebphone', () => ({
  useSipWebphone: () => state.sip,
}));
vi.mock('dashboard/stores/calls', () => ({
  useCallsStore: () => ({ hasActiveCall: false, hasIncomingCall: false }),
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({ isInitiating: ref(false) }),
}));
const options = {
  props: { accountId: 7, userId: 91, allowed: true },
  global: {
    stubs: {
      Dialog: {
        name: 'Dialog',
        props: ['dismissible', 'closeOnClickOutside', 'showCloseButton'],
        methods: { open() {}, close() {} },
        template: '<div><slot /></div>',
      },
    },
  },
};
beforeEach(() => {
  state.sip = Object.fromEntries(
    Object.entries({
      accountId: 7,
      hasCall: false,
      registered: true,
      credential: { extension: '1234' },
      destination: '',
      callId: 'session-a',
      errorMessage: '',
    }).map(([k, v]) => [k, ref(v)])
  );
  state.sip.call = vi.fn().mockImplementation(async () => {
    state.sip.hasCall.value = true;
  });
});
describe('outbound confirmation without changing selected attendance', () => {
  it('keeps an in-flight originate visible until it resolves instead of dismissing and losing its reviewed draft', async () => {
    let resolve;
    state.sip.call.mockImplementation(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = mount(OutboundVoiceDialog, {
      ...options,
      props: { ...options.props, initialPhone: '12345678' },
    });
    await wrapper.get('[data-outbound-reason]').setValue('Retorno');
    await wrapper.get('[data-outbound-call]').trigger('click');
    const dialog = wrapper.getComponent({ name: 'Dialog' });
    expect(dialog.props('dismissible')).toBe(false);
    expect(dialog.props('closeOnClickOutside')).toBe(false);
    expect(dialog.props('showCloseButton')).toBe(false);
    resolve(false);
    await flushPromises();
    expect(dialog.props('dismissible')).toBe(true);
    wrapper.unmount();
  });
  it('opens a dialer without originating a call and allows the agent to annotate it afterwards', async () => {
    const wrapper = mount(OutboundVoiceDialog, {
      ...options,
      props: { ...options.props, initialPhone: '12345678' },
    });
    await flushPromises();
    expect(state.sip.call).not.toHaveBeenCalled();
    expect(
      wrapper.get('[data-outbound-call]').attributes('disabled')
    ).toBeUndefined();
    expect(
      wrapper.get('[data-outbound-source]').attributes('readonly')
    ).toBeDefined();
    wrapper.unmount();
  });
  it('supports keypad entry and correction before the explicit call action', async () => {
    const wrapper = mount(OutboundVoiceDialog, options);
    await wrapper.get('[data-outbound-tone="1"]').trigger('click');
    await wrapper.get('[data-outbound-tone="4"]').trigger('click');
    await wrapper.get('[data-outbound-tone="1"]').trigger('click');
    await wrapper.get('[data-outbound-tone="0"]').trigger('click');
    expect(wrapper.get('[data-outbound-phone]').element.value).toBe('1410');
    await wrapper.get('[data-outbound-backspace]').trigger('click');
    expect(wrapper.get('[data-outbound-phone]').element.value).toBe('141');
    expect(state.sip.call).not.toHaveBeenCalled();
    await wrapper.get('[data-outbound-call]').trigger('click');
    await flushPromises();
    expect(state.sip.destination.value).toBe('141');
    expect(wrapper.emitted('started')[0][0].reason).toBe('');
    wrapper.unmount();
  });
  it('starts only the reviewed number from the already authorized extension', async () => {
    const wrapper = mount(OutboundVoiceDialog, {
      ...options,
      props: { ...options.props, initialPhone: '12345678' },
    });
    await wrapper.get('[data-outbound-reason]').setValue('Retorno solicitado');
    await wrapper.get('[data-outbound-call]').trigger('click');
    await flushPromises();
    expect(state.sip.destination.value).toBe('12345678');
    expect(state.sip.call).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('started')[0][0]).toMatchObject({
      sessionId: 'session-a',
      reason: 'Retorno solicitado',
      accountId: 7,
    });
    wrapper.unmount();
  });
  it('does not dial a second call or use another Account credential', async () => {
    state.sip.hasCall.value = true;
    const wrapper = mount(OutboundVoiceDialog, options);
    await wrapper.get('[data-outbound-phone]').setValue('12345678');
    await wrapper.get('[data-outbound-reason]').setValue('Retorno');
    expect(
      wrapper.get('[data-outbound-call]').attributes('disabled')
    ).toBeDefined();
    expect(wrapper.get('[data-outbound-blocked]').text()).toContain(
      'VOICE_V4.CALL_ALREADY_ACTIVE'
    );
    state.sip.hasCall.value = false;
    state.sip.accountId.value = 8;
    await flushPromises();
    expect(
      wrapper.get('[data-outbound-call]').attributes('disabled')
    ).toBeDefined();
    expect(state.sip.call).not.toHaveBeenCalled();
    wrapper.unmount();
  });
});
