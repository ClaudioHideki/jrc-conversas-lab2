import { flushPromises, mount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mockRoute, mockRouter } from 'vue-router';
import { mockSipState } from './useSipWebphone';
import SipCallWidget from './SipCallWidget.vue';
import { ref as vueRef } from 'vue';
import { useEmbeddedSoftphone } from './useEmbeddedSoftphone';

vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const routeState = reactive({ name: 'ramal_index' });
  const router = { replace: vi.fn().mockResolvedValue(undefined) };
  return {
    useRoute: () => routeState,
    useRouter: () => router,
    mockRoute: routeState,
    mockRouter: router,
  };
});

vi.mock('./useSipWebphone', async () => {
  const { ref, shallowRef } = await import('vue');
  const sipState = {
    accountId: ref(1),
    status: ref('Chamada recebida'),
    incoming: ref(false),
    established: ref(false),
    remoteNumber: ref('11999999999'),
    remoteStream: shallowRef(null),
    errorMessage: ref(''),
    answer: vi.fn(),
    reject: vi.fn(),
    hangup: vi.fn(),
  };
  return { useSipWebphone: () => sipState, mockSipState: sipState };
});

describe('SipCallWidget', () => {
  let wrapper;
  beforeEach(() => {
    mockRoute.name = 'ramal_index';
    mockRoute.params = { accountId: '1' };
    mockSipState.accountId.value = 1;
    mockRouter.replace.mockClear();
    mockRouter.replace.mockResolvedValue(undefined);
    mockSipState.incoming.value = false;
    mockSipState.established.value = false;
    mockSipState.answer.mockClear();
    mockSipState.reject.mockClear();
    vi.stubGlobal(
      'Audio',
      vi.fn(() => ({
        pause: vi.fn(),
        play: vi.fn().mockResolvedValue(undefined),
        currentTime: 0,
        loop: false,
        volume: 1,
      }))
    );
  });
  afterEach(() => {
    wrapper?.unmount();
    vi.unstubAllGlobals();
  });

  it('shows answer and reject actions for an incoming call on the Ramal page', async () => {
    mockSipState.incoming.value = true;
    wrapper = mount(SipCallWidget);
    await flushPromises();

    expect(wrapper.text()).toContain('Chamada recebida');
    expect(wrapper.text()).toContain('11999999999');

    const buttons = wrapper.findAll('button');
    await buttons.find(button => button.text() === 'Atender').trigger('click');
    await buttons.find(button => button.text() === 'Recusar').trigger('click');

    expect(mockSipState.answer).toHaveBeenCalledOnce();
    expect(mockSipState.reject).toHaveBeenCalledOnce();
  });

  it('closes when the call is no longer incoming', async () => {
    mockSipState.incoming.value = true;
    wrapper = mount(SipCallWidget);
    expect(wrapper.find('aside').exists()).toBe(true);

    mockSipState.incoming.value = false;
    await wrapper.vm.$nextTick();

    expect(wrapper.find('aside').exists()).toBe(false);
  });
  it('never renders controls or audio for the previously active Account', async () => {
    mockRoute.name = 'inbox_view';
    mockRoute.params = { accountId: '2' };
    mockSipState.incoming.value = true;
    wrapper = mount(SipCallWidget);
    await flushPromises();
    expect(wrapper.find('aside').exists()).toBe(false);
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(Audio.mock.results[0].value.play).not.toHaveBeenCalled();
  });
  it('rechecks Account identity before handling a stale answer click', async () => {
    mockSipState.incoming.value = true;
    wrapper = mount(SipCallWidget);
    const button = wrapper
      .findAll('button')
      .find(item => item.text() === 'Atender');
    mockRoute.params = { accountId: '2' };
    await button.trigger('click');
    expect(mockSipState.answer).not.toHaveBeenCalled();
  });
  it('keeps a single global audio renderer and ringtone while embedded controls hide the floating widget', async () => {
    mockRoute.name = 'inbox_view';
    mockRoute.params = { accountId: '1' };
    mockSipState.incoming.value = true;
    const enabled = vueRef(true);
    const host = mount({
      setup() {
        useEmbeddedSoftphone(vueRef(1), enabled, vi.fn());
      },
      template: '<div />',
    });
    wrapper = mount(SipCallWidget);
    await flushPromises();
    expect(wrapper.find('aside').exists()).toBe(false);
    expect(wrapper.findAll('audio')).toHaveLength(1);
    const audio = wrapper.get('audio').element;
    expect(Audio).toHaveBeenCalledOnce();
    const ringtone = Audio.mock.results[0].value;
    expect(ringtone.play).toHaveBeenCalledOnce();
    enabled.value = false;
    await flushPromises();
    expect(wrapper.find('aside').exists()).toBe(true);
    expect(wrapper.get('audio').element).toBe(audio);
    expect(ringtone.play).toHaveBeenCalledOnce();
    host.unmount();
  });

  it('opens Ramal on desktop account entry without reloading the renderer', async () => {
    vi.stubGlobal('jrcSoftphoneDesktop', {});
    mockRoute.name = 'dashboard';
    mockRoute.params = { accountId: '1' };
    wrapper = mount(SipCallWidget);
    await flushPromises();
    expect(mockRouter.replace).toHaveBeenCalledWith({
      name: 'ramal_index',
      params: { accountId: '1' },
    });
    mockRoute.name = 'contacts_edit';
    await flushPromises();
    expect(mockRouter.replace).toHaveBeenCalledOnce();
  });

  it('does not redirect ordinary browser navigation', async () => {
    mockRoute.name = 'contacts_edit';
    mockRoute.params = { accountId: '1' };
    wrapper = mount(SipCallWidget);
    await flushPromises();
    expect(mockRouter.replace).not.toHaveBeenCalled();
  });
});
