import { config, flushPromises, shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR';
import en from 'dashboard/i18n/locale/en';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mockState } from './useSipWebphone';
import WebphonePage from './WebphonePage.vue';
import ContactAPI from 'dashboard/api/contacts';
import CurrentContactCard from './CurrentContactCard.vue';
import CallHistoryPanel from './CallHistoryPanel.vue';
import VideoConferenceSettingsAPI from 'dashboard/api/videoConferenceSettings';
import { openVideoConferencePopup } from 'dashboard/helper/videoConference';

vi.mock('dashboard/api/videoConferenceSettings', () => ({
  default: { getFreshMine: vi.fn() },
}));
vi.mock('dashboard/helper/videoConference', () => ({
  openVideoConferencePopup: vi.fn(),
}));

vi.mock('./CallHistoryPanel.vue', () => ({ default: { template: '<div />' } }));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: 1 }, query: {} }),
  useRouter: () => ({ push: vi.fn() }),
}));
vi.mock('dashboard/api/contacts', () => ({
  default: { get: vi.fn().mockResolvedValue({ data: { payload: [] } }) },
}));
vi.mock('./useSipWebphone', async () => {
  const { ref } = await import('vue');
  const state = {
    credential: ref({ extension: '101' }),
    loading: ref(false),
    connecting: ref(false),
    status: ref('Em chamada'),
    destination: ref(''),
    duration: ref('00:00'),
    incoming: ref(false),
    established: ref(true),
    muted: ref(false),
    held: ref(false),
    holdPending: ref(false),
    transferring: ref(false),
    errorMessage: ref(''),
    remoteNumber: ref('202'),
    remoteStream: ref(null),
    configured: ref(true),
    registered: ref(true),
    hasCall: ref(true),
    extensionEnabled: ref(true),
    transferCall: vi.fn(),
    call: vi.fn(),
    answer: vi.fn(),
    reject: vi.fn(),
    hangup: vi.fn(),
    setMuted: vi.fn(),
    setHold: vi.fn(),
    turnOnExtension: vi.fn(),
    turnOffExtension: vi.fn(),
    pressKey: vi.fn(),
  };
  return { useSipWebphone: () => state, mockState: state };
});

describe('transfer form', () => {
  let wrapper;
  const originalPlugins = config.global.plugins;
  beforeEach(() => {
    config.global.plugins = [
      createI18n({
        legacy: false,
        locale: 'pt_BR',
        fallbackLocale: 'en',
        messages: { pt_BR: ptBR, en },
      }),
    ];
    vi.stubGlobal('Notification', { permission: 'default' });
    mockState.transferring.value = false;
    mockState.holdPending.value = false;
    mockState.established.value = true;
    mockState.hasCall.value = true;
    mockState.destination.value = '';
    vi.stubGlobal(
      'Audio',
      vi.fn(() => ({
        pause: vi.fn(),
        play: vi.fn().mockResolvedValue(undefined),
      }))
    );
    wrapper = shallowMount(WebphonePage);
  });
  afterEach(() => {
    wrapper.unmount();
    config.global.plugins = originalPlugins;
    vi.unstubAllGlobals();
  });
  it('renders the call notification action in pt-BR', () => {
    expect(wrapper.text()).toContain('Ativar notificações de chamadas');
    expect(wrapper.text()).not.toContain('Enable call notifications');
  });
  it('preserves mode and destination after failure, clears only after successful sequence', async () => {
    wrapper.vm.selectTransferMode('supervised');
    wrapper.vm.transferDestination = '202';
    mockState.transferCall.mockResolvedValue(false);
    await wrapper.vm.submitTransfer();
    await flushPromises();
    expect(wrapper.vm.transferMode).toBe('supervised');
    expect(wrapper.vm.transferDestination).toBe('202');
    mockState.transferCall.mockResolvedValue(true);
    await wrapper.vm.submitTransfer();
    expect(wrapper.vm.transferMode).toBe('');
    expect(wrapper.vm.transferDestination).toBe('');
  });
  it('prevents a repeated submission and disables transfer/hold controls while pending', async () => {
    wrapper.vm.selectTransferMode('immediate');
    wrapper.vm.transferDestination = '202';
    mockState.transferring.value = true;
    await wrapper.vm.$nextTick();
    await wrapper.vm.submitTransfer();
    expect(mockState.transferCall).not.toHaveBeenCalled();
    expect(
      wrapper.find('.jrc-transfer-submit').attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper.find('.jrc-transfer-input').attributes('disabled')
    ).toBeDefined();
  });
  it.each(['immediate', 'supervised'])(
    'reuses %s transfer in the mini, retaining failures and blocking hold/pending submissions',
    async mode => {
      await wrapper.setProps({ compact: true });
      wrapper.vm.selectTransferMode(mode);
      wrapper.vm.transferDestination = '202';
      mockState.transferCall.mockResolvedValue(false);
      await wrapper.vm.submitTransfer();
      expect(mockState.transferCall).toHaveBeenLastCalledWith(mode, '202');
      expect(wrapper.vm.transferDestination).toBe('202');
      mockState.holdPending.value = true;
      mockState.transferCall.mockClear();
      await wrapper.vm.submitTransfer();
      expect(mockState.transferCall).not.toHaveBeenCalled();
      mockState.holdPending.value = false;
      mockState.transferCall.mockResolvedValue(true);
      await wrapper.vm.submitTransfer();
      expect(wrapper.vm.transferMode).toBe('');
      mockState.established.value = false;
      wrapper.vm.selectTransferMode('immediate');
      wrapper.vm.transferDestination = '202';
      mockState.transferCall.mockClear();
      await wrapper.vm.submitTransfer();
      expect(mockState.transferCall).not.toHaveBeenCalled();
    }
  );
  it('loads the same contacts and history only on their mini tabs and prevents dialing while another channel is busy', async () => {
    wrapper.unmount();
    ContactAPI.get.mockClear();
    wrapper = shallowMount(WebphonePage, { props: { compact: true } });
    expect(ContactAPI.get).not.toHaveBeenCalled();
    expect(wrapper.findComponent(CallHistoryPanel).exists()).toBe(false);
    wrapper.vm.activeTab = 'contacts';
    await flushPromises();
    expect(ContactAPI.get).toHaveBeenCalledWith(1, '-last_activity_at');
    expect(wrapper.findComponent(CurrentContactCard).props('accountId')).toBe(
      1
    );
    wrapper.vm.activeTab = 'history';
    await wrapper.vm.$nextTick();
    expect(wrapper.findComponent(CallHistoryPanel).exists()).toBe(true);
    await wrapper.setProps({ externalBusy: true });
    mockState.hasCall.value = false;
    mockState.call.mockClear();
    wrapper.vm.dialContact({ id: 9, phone_number: '+5511999990000' });
    await wrapper.vm.startCall();
    expect(mockState.call).not.toHaveBeenCalled();
    expect(mockState.destination.value).toBe('');
  });
  it('allows extension controls, keeps the shared session on minimize and avoids a second audio element', async () => {
    wrapper.unmount();
    wrapper = shallowMount(WebphonePage, { props: { compact: true } });
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(wrapper.find('#quick-ramal-keypad').isVisible()).toBe(false);
    await wrapper
      .find('button[aria-controls="quick-ramal-keypad"]')
      .trigger('click');
    // JSDOM retains the previous computed display after v-show clears it.
    expect(wrapper.find('#quick-ramal-keypad').element.style.display).toBe('');
    expect(
      wrapper
        .find('button[aria-controls="quick-ramal-keypad"]')
        .attributes('aria-expanded')
    ).toBe('true');
    await wrapper.find('.jrc-key-button').trigger('click');
    expect(mockState.pressKey).toHaveBeenCalledWith('1');
    expect(wrapper.text()).toContain('Desligar Ramal');
    mockState.hasCall.value = false;
    await wrapper.vm.toggleExtension();
    expect(mockState.turnOffExtension).toHaveBeenCalled();
    wrapper.unmount();
    expect(mockState.hangup).not.toHaveBeenCalled();
  });
  it('opens the existing conference popup without navigating and respects conference access', async () => {
    await wrapper.setProps({ compact: true, allowConference: false });
    wrapper.vm.openVideoConference();
    expect(openVideoConferencePopup).not.toHaveBeenCalled();
    await wrapper.setProps({ allowConference: true });
    wrapper.vm.openVideoConference();
    const options = openVideoConferencePopup.mock.calls[0][0];
    expect(options.preferredRole).toBeNull();
    VideoConferenceSettingsAPI.getFreshMine.mockResolvedValue({
      data: { moderator_url: 'https://meet.example.test/room' },
    });
    expect(await options.getSetting()).toEqual({
      moderator_url: 'https://meet.example.test/room',
    });
    options.onBlocked();
    expect(wrapper.vm.conferenceMessage).not.toBe('');
  });
  it('prevents duplicate mini dialing while call setup is pending', async () => {
    await wrapper.setProps({ compact: true });
    mockState.hasCall.value = false;
    mockState.destination.value = '202';
    let complete;
    mockState.call.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          complete = resolve;
        })
    );
    const pending = wrapper.vm.startCall();
    await wrapper.vm.startCall();
    expect(mockState.call).toHaveBeenCalledTimes(1);
    expect(wrapper.emitted('dialing')).toEqual([[true]]);
    complete();
    await pending;
    expect(wrapper.emitted('dialing')).toEqual([[true], [false]]);
  });
});
