import { flushPromises, shallowMount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mockState } from './useSipWebphone';
import WebphonePage from './WebphonePage.vue';

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
  beforeEach(() => {
    mockState.transferring.value = false;
    mockState.holdPending.value = false;
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
    vi.unstubAllGlobals();
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
});
