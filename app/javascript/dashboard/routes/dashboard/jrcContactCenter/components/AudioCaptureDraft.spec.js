import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ref, shallowRef } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { emitter } from 'shared/helpers/mitt';
import AudioCaptureDraft from './AudioCaptureDraft.vue';

const mocks = vi.hoisted(() => ({ capture: null }));
vi.mock('../composables/useInstitutionalAudioCapture', () => ({
  useInstitutionalAudioCapture: () => mocks.capture,
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const setup = () =>
  mount(AudioCaptureDraft, {
    props: {
      contextKey: 'SYNTHETIC account1/unit10/profileA',
      disabled: false,
      maxBytes: 1000,
    },
  });
const ready = () => {
  mocks.capture.phase.value = 'ready';
  mocks.capture.file.value = new File(['SYNTHETIC recording'], 'capture.ogg', {
    type: 'audio/ogg',
  });
};
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  })
);
beforeEach(() => {
  mocks.capture = {
    phase: ref('idle'),
    error: ref(''),
    file: shallowRef(null),
    byteSize: ref(0),
    start: vi.fn(),
    stop: vi.fn(),
    reset: vi.fn(),
  };
  mocks.capture.reset.mockImplementation(() => {
    mocks.capture.phase.value = 'idle';
    mocks.capture.file.value = null;
  });
  vi.stubGlobal('URL', {
    createObjectURL: vi.fn().mockReturnValue('blob:SYNTHETIC-local-capture'),
    revokeObjectURL: vi.fn(),
  });
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => {});
});

describe('local capture draft UI (lifecycle fixtures, not physical microphone proof)', () => {
  it('starts only on explicit action and offers no automatic upload or autoplay', async () => {
    const wrapper = setup();
    expect(mocks.capture.start).not.toHaveBeenCalled();
    expect(wrapper.find('audio').exists()).toBe(false);
    await wrapper.get('[data-start-institutional-capture]').trigger('click');
    expect(mocks.capture.start).toHaveBeenCalledOnce();
    expect(wrapper.emitted('discard')).toEqual([[]]);
    ready();
    await flushPromises();
    expect(wrapper.get('audio').attributes('autoplay')).toBeUndefined();
    expect(wrapper.emitted('selected')).toBeUndefined();
    await wrapper.get('[data-use-institutional-capture]').trigger('click');
    expect(wrapper.emitted('selected')).toEqual([[mocks.capture.file.value]]);
  });

  it('reports ongoing capture to the existing save guard and stops only through the explicit stop action', async () => {
    const wrapper = setup();
    mocks.capture.phase.value = 'recording';
    await flushPromises();
    expect(wrapper.emitted('busy').at(-1)).toEqual([true]);
    expect(
      wrapper.get('[data-start-institutional-capture]').element.disabled
    ).toBe(true);
    await wrapper.get('[data-stop-institutional-capture]').trigger('click');
    expect(mocks.capture.stop).toHaveBeenCalledOnce();
    mocks.capture.phase.value = 'ready';
    await flushPromises();
    expect(wrapper.emitted('busy').at(-1)).toEqual([false]);
  });

  it('discards only the unsaved capture and revokes its local preview URL', async () => {
    const wrapper = setup();
    ready();
    await flushPromises();
    await wrapper.get('[data-discard-institutional-capture]').trigger('click');
    expect(mocks.capture.reset).toHaveBeenCalledOnce();
    expect(wrapper.emitted('discard')).toEqual([[]]);
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:SYNTHETIC-local-capture'
    );
    expect(wrapper.find('audio').exists()).toBe(false);
  });

  it('removes preview access immediately when controls become disabled and never emits a selection', async () => {
    const wrapper = setup();
    ready();
    await flushPromises();
    await wrapper.setProps({ disabled: true });
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:SYNTHETIC-local-capture'
    );
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(wrapper.emitted('selected')).toBeUndefined();
  });

  it('cooperates with the native shared audio pause event and releases its URL on unmount', async () => {
    const wrapper = setup();
    ready();
    await flushPromises();
    const pause = wrapper.get('audio').element.pause;
    pause.mockClear();
    emitter.emit('pause_playing_audio', -1);
    expect(pause).toHaveBeenCalledOnce();
    wrapper.unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:SYNTHETIC-local-capture'
    );
  });
});
