import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import InboxVoicePanel from './InboxVoicePanel.vue';
import InboxChannelGroups from './InboxChannelGroups.vue';
import { openEmbeddedSoftphone } from '../webphone/useEmbeddedSoftphone';
import API from 'dashboard/api/jrcContactCenter';

const state = vi.hoisted(() => ({ sip: null, calls: {}, initiating: null }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/stores/calls', () => ({ useCallsStore: () => state.calls }));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  useWhatsappCallSession: () => ({ isInitiating: state.initiating }),
}));
vi.mock('../webphone/useSipWebphone', () => ({
  useSipWebphone: () => state.sip,
}));
vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { saveCallObservations: vi.fn(), call: vi.fn() },
}));
enableAutoUnmount(afterEach);
const props = {
  accountId: 1,
  allowed: true,
  sessionView: true,
  capabilities: {
    sip_webrtc: 'available',
    hold: 'available',
    transfer_blind: 'available',
    transfer_attended: 'available',
  },
};
const record = {
  id: 7,
  provider: 'jrc_pabx',
  external_session_id: 'native-7',
  status: 'connected',
  direction: 'inbound',
  ani: '1410',
  dnis: '1411',
  lock_version: 3,
  started_at: '2026-10-23T12:00:00Z',
  metadata: { attendance_observations: { text: 'Texto salvo' } },
  queue: { name: 'Fila sintética' },
  attendant: { name: 'Agente sintético' },
};
const selected = {
  ...props,
  sessionView: false,
  nativeCallId: 7,
  callRecord: record,
  customer: { name: 'Cliente sintético' },
};
const button = (wrapper, key) => wrapper.get(`[data-voice-action="${key}"]`);
beforeEach(() => {
  state.sip = Object.fromEntries(
    Object.entries({
      accountId: 1,
      callId: 'native-7',
      incoming: false,
      hasCall: false,
      established: false,
      held: false,
      muted: false,
      holdPending: false,
      transferring: false,
      errorMessage: '',
      credential: { extension: '1410' },
      remoteNumber: '1410',
      duration: '03:27',
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
    'turnOnExtension',
    'turnOffExtension',
  ].forEach(key => {
    state.sip[key] = vi.fn();
  });
  state.sip.transferCall = vi.fn().mockResolvedValue(true);
  state.calls = { hasActiveCall: false, hasIncomingCall: false };
  state.initiating = ref(false);
  vi.clearAllMocks();
});
describe('central shared voice panel', () => {
  it('opens the central dialer and prefills a customer number without placing a call', async () => {
    const wrapper = mount(InboxVoicePanel, { props, attachTo: document.body });
    expect(openEmbeddedSoftphone(1, '+55 (11) 98765-0000')).toBe(true);
    await flushPromises();
    expect(wrapper.emitted('open')).toHaveLength(1);
    expect(wrapper.get('[data-central-dialer] input').element.value).toBe(
      '11987650000'
    );
    expect(document.activeElement).toBe(wrapper.get('input[type=tel]').element);
    expect(state.sip.call).not.toHaveBeenCalled();
    await wrapper.get('[data-central-dialer]').trigger('submit');
    expect(state.sip.call).toHaveBeenCalledOnce();
    expect(openEmbeddedSoftphone(2)).toBe(false);
  });
  it('releases ownership when authorization or Account changes and never creates a SIP client', async () => {
    const wrapper = mount(InboxVoicePanel, { props });
    await wrapper.setProps({ accountId: 2 });
    expect(openEmbeddedSoftphone(1)).toBe(false);
    expect(openEmbeddedSoftphone(2)).toBe(false);
    state.sip.accountId.value = 2;
    await flushPromises();
    expect(openEmbeddedSoftphone(2)).toBe(true);
    await wrapper.setProps({ allowed: false });
    expect(openEmbeddedSoftphone(2)).toBe(false);
    expect(wrapper.get('input[type=tel]').attributes('disabled')).toBeDefined();
    expect(state.sip.initialize).toBeUndefined();
  });
  it('allows the independently authorized SIP extension while the external API contract remains pending', () => {
    mount(InboxVoicePanel, {
      props: { ...props, capabilities: { sip_webrtc: 'pending_contract' } },
    });
    expect(openEmbeddedSoftphone(1)).toBe(true);
  });
  it('does not claim the phone when SIP is unavailable', () => {
    mount(InboxVoicePanel, { props: { ...props, capabilities: {} } });
    expect(openEmbeddedSoftphone(1)).toBe(false);
  });
  it.each(['qualification', 'active', 'incoming', 'initiating'])(
    'blocks starting another call during %s',
    async reason => {
      state.calls.hasActiveCall = reason === 'active';
      state.calls.hasIncomingCall = reason === 'incoming';
      state.initiating.value = reason === 'initiating';
      state.sip.destination.value = '1411';
      const wrapper = mount(InboxVoicePanel, {
        props: { ...props, qualificationPending: reason === 'qualification' },
      });
      await wrapper.get('[data-central-dialer]').trigger('submit');
      expect(state.sip.call).not.toHaveBeenCalled();
    }
  );
  it('presents incoming identity and real answer/reject actions only in its Account', async () => {
    state.sip.incoming.value = true;
    state.sip.hasCall.value = true;
    const wrapper = mount(InboxVoicePanel, { props });
    await flushPromises();
    expect(wrapper.emitted('open')).toHaveLength(1);
    expect(wrapper.get('[data-voice-status]').text()).toContain(
      'STATES.incoming'
    );
    await wrapper
      .get('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.ANSWER"]')
      .trigger('click');
    expect(state.sip.answer).toHaveBeenCalledOnce();
    await wrapper.setProps({ accountId: 2 });
    expect(
      wrapper
        .find('button[aria-label="JRC_CONTACT_CENTER.INBOX_360.ANSWER"]')
        .exists()
    ).toBe(false);
    expect(wrapper.vm.canEnd).toBe(false);
  });
  it('renders the selected active call with identity, status, controls and persisted information', async () => {
    state.sip.established.value = true;
    state.sip.hasCall.value = true;
    const wrapper = mount(InboxVoicePanel, { props: selected });
    expect(wrapper.get('[data-voice-identity]').text()).toContain(
      'Cliente sintético'
    );
    expect(wrapper.text()).toContain('Fila sintética');
    expect(wrapper.text()).toContain('Agente sintético');
    expect(wrapper.get('[data-voice-status]').text()).toContain('03:27');
    await button(wrapper, 'MUTE').trigger('click');
    expect(state.sip.setMuted).toHaveBeenCalledWith(true);
    await flushPromises();
    await button(wrapper, 'HOLD').trigger('click');
    expect(state.sip.setHold).toHaveBeenCalledWith(true);
    await flushPromises();
    await button(wrapper, 'KEYPAD').trigger('click');
    await flushPromises();
    await wrapper.get('[data-call-keypad] button').trigger('click');
    expect(state.sip.pressKey).toHaveBeenCalledWith('1');
  });
  it.each(['account', 'session', 'capability', 'permission'])(
    'prevents selected-call control with mismatched %s',
    async mismatch => {
      state.sip.established.value = true;
      state.sip.hasCall.value = true;
      if (mismatch === 'account') state.sip.accountId.value = 2;
      if (mismatch === 'session') state.sip.callId.value = 'different';
      const wrapper = mount(InboxVoicePanel, {
        props: {
          ...selected,
          ...(mismatch === 'capability'
            ? { capabilities: { sip_webrtc: 'pending_contract' } }
            : {}),
          ...(mismatch === 'permission' ? { allowed: false } : {}),
        },
      });
      expect(button(wrapper, 'MUTE').attributes('disabled')).toBeDefined();
      await button(wrapper, 'MUTE').trigger('click');
      await wrapper.vm.endCall();
      expect(state.sip.setMuted).not.toHaveBeenCalled();
      expect(state.sip.hangup).not.toHaveBeenCalled();
    }
  );
  it('distinguishes ambiguous customers without selecting the first match', () => {
    const wrapper = mount(InboxVoicePanel, {
      props: { ...selected, ambiguous: true },
    });
    expect(wrapper.get('[data-voice-identity]').text()).toContain(
      'JRC_CONTACT_CENTER.CALL.AMBIGUOUS'
    );
    expect(wrapper.get('[data-voice-identity]').text()).not.toContain(
      'Cliente sintético'
    );
  });
  it('reuses the transfer service with the human extension and supported mode', async () => {
    state.sip.established.value = true;
    state.sip.hasCall.value = true;
    const wrapper = mount(InboxVoicePanel, { props: selected });
    await button(wrapper, 'TRANSFER').trigger('click');
    await flushPromises();
    await wrapper.get('input[inputmode=numeric]').setValue('1411');
    await wrapper.get('select').setValue('supervised');
    await wrapper
      .get('input[inputmode=numeric]')
      .element.closest('form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await flushPromises();
    expect(state.sip.transferCall).toHaveBeenCalledWith('supervised', '1411');
  });
  it('saves observations, rereads the saved content on remount, and preserves edits on conflicts', async () => {
    API.saveCallObservations.mockResolvedValue({
      data: {
        item: {
          ...record,
          lock_version: 4,
          metadata: { attendance_observations: { text: 'Atualizado' } },
        },
      },
    });
    let wrapper = mount(InboxVoicePanel, { props: selected });
    expect(wrapper.get('textarea').element.value).toBe('Texto salvo');
    await wrapper.get('textarea').setValue('Atualizado');
    await wrapper.get('[data-call-observations]').trigger('submit');
    await flushPromises();
    expect(API.saveCallObservations).toHaveBeenCalledWith(1, 7, {
      text: 'Atualizado',
      lock_version: 3,
    });
    const saved = wrapper.emitted('updated')[0][0];
    wrapper.unmount();
    wrapper = mount(InboxVoicePanel, {
      props: { ...selected, callRecord: saved },
    });
    expect(wrapper.get('textarea').element.value).toBe('Atualizado');
    API.saveCallObservations.mockRejectedValue({ response: { status: 409 } });
    await wrapper.get('textarea').setValue('Não perder');
    await wrapper.get('[data-call-observations]').trigger('submit');
    await flushPromises();
    expect(wrapper.get('textarea').element.value).toBe('Não perder');
    expect(wrapper.get('[role=alert]').text()).toContain('NOTE_CONFLICT');
  });
  it('does not move an old save result into another Account or call', async () => {
    let resolve;
    API.saveCallObservations.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = mount(InboxVoicePanel, { props: selected });
    await wrapper.get('textarea').setValue('Pendente');
    await wrapper.get('[data-call-observations]').trigger('submit');
    await wrapper.setProps({
      accountId: 2,
      nativeCallId: 8,
      callRecord: { ...record, id: 8, metadata: {} },
    });
    resolve({ data: { item: record } });
    await flushPromises();
    expect(wrapper.emitted('updated')).toBeUndefined();
    expect(wrapper.get('textarea').element.value).toBe('');
  });
  it('requires a persisted authorized call record before saving observations', async () => {
    state.sip.hasCall.value = true;
    const wrapper = mount(InboxVoicePanel, { props });
    expect(wrapper.get('textarea').attributes('disabled')).toBeDefined();
    await wrapper.get('[data-call-observations]').trigger('submit');
    expect(API.saveCallObservations).not.toHaveBeenCalled();
  });
});
describe('terminated SIP timing', () => {
  it('freezes the observed session duration until the backend confirms its end', async () => {
    state.sip.established.value = true;
    state.sip.hasCall.value = true;
    const wrapper = mount(InboxVoicePanel, {
      props: { ...selected, elapsed: '00:03:29' },
    });
    await flushPromises();
    state.sip.established.value = false;
    state.sip.hasCall.value = false;
    state.sip.sessionState.value = 'Terminated';
    state.sip.duration.value = '00:00';
    await wrapper.setProps({ elapsed: '00:04:00' });
    expect(wrapper.get('[data-voice-status]').text()).toContain('STATES.ended');
    expect(wrapper.get('[data-voice-status]').text()).toContain('03:27');
    expect(wrapper.get('[data-voice-status]').text()).not.toContain('00:04:00');
    await wrapper.setProps({
      callRecord: { ...record, ended_at: '2026-10-23T12:03:28Z' },
      elapsed: '00:03:28',
    });
    expect(wrapper.get('[data-voice-status]').text()).toContain('00:03:28');
  });
});
describe('voice list composition', () => {
  it('lists Voice before WhatsApp with selection, phone, state and real duration, without a dialer', async () => {
    const wrapper = mount(InboxChannelGroups, {
      props: {
        calls: [record],
        channels: [
          { key: 'whatsapp', label: 'WhatsApp' },
          { key: 'voice', label: 'Voz' },
        ],
        currentCallId: 7,
        selectedCustomerName: 'Cliente sintético',
        now: Date.parse('2026-10-23T12:03:27Z'),
        inboxFor: () => ({}),
      },
    });
    const group = wrapper.findAll('section')[0];
    expect(group.attributes('data-channel')).toBe('voice');
    expect(group.text()).toContain('Cliente sintético');
    expect(group.text()).toContain('1410');
    expect(group.text()).toContain('00:03:27');
    expect(group.find('input').exists()).toBe(false);
    expect(group.get('[aria-pressed=true]').exists()).toBe(true);
    await group.get('[aria-pressed=true]').trigger('click');
    expect(wrapper.emitted('selectCall')[0][0]).toEqual(record);
  });
});
