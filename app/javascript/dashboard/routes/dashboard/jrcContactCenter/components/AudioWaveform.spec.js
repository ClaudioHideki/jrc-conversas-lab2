import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import WaveSurfer from 'wavesurfer.js';
import AudioWaveform from './AudioWaveform.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('wavesurfer.js', () => ({ default: { create: vi.fn() } }));
const metadata = { duration_ms: 2000, channels: 1 };
let surfaces;
const fixture = (overrides = {}) => {
  const media = document.createElement('audio');
  media.src = 'blob:SYNTHETIC-verified';
  return mount(AudioWaveform, {
    props: {
      url: media.src,
      media,
      metadata: { ...metadata },
      byteSize: 32044,
      ...overrides,
    },
  });
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  surfaces = [];
  WaveSurfer.create.mockImplementation(options => {
    const handlers = {};
    const surface = {
      options,
      handlers,
      destroy: vi.fn(),
      on: vi.fn((name, callback) => {
        handlers[name] = callback;
      }),
      getDecodedData: vi.fn(() => ({
        length: 16000,
        duration: 2,
        numberOfChannels: 1,
      })),
    };
    surfaces.push(surface);
    return surface;
  });
});

describe('institutional waveform lifecycle (library mock, not native decoder proof)', () => {
  it('reuses the exact verified blob and existing media controls without autoplay or a second API request', async () => {
    const wrapper = fixture();
    await flushPromises();
    expect(WaveSurfer.create).toHaveBeenCalledOnce();
    expect(surfaces[0].options).toMatchObject({
      media: wrapper.props('media'),
      url: 'blob:SYNTHETIC-verified',
      autoplay: false,
      interact: false,
      sampleRate: 8000,
    });
    expect(surfaces[0].options).not.toHaveProperty('peaks');
    expect(wrapper.find('audio').exists()).toBe(false);
    expect(wrapper.get('[role="img"]').attributes('aria-busy')).toBe('true');
  });

  it('reports ready only after actual decode and drawing, preserving zero-valued silent audio samples', async () => {
    const wrapper = fixture();
    await flushPromises();
    expect(wrapper.attributes('data-audio-waveform')).toBe('LOADING');
    surfaces[0].handlers.redrawcomplete();
    await flushPromises();
    expect(wrapper.attributes('data-audio-waveform')).toBe('READY');
    expect(wrapper.attributes('data-decoded-samples')).toBe('16000');
    expect(wrapper.get('[role="img"]').attributes('aria-busy')).toBe('false');
  });

  it.each([
    { byteSize: 0 },
    { byteSize: 20 * 1024 * 1024 + 1 },
    { byteSize: '32044' },
    { metadata: { ...metadata, duration_ms: 0 } },
    { metadata: { ...metadata, duration_ms: 600001 } },
    { metadata: { ...metadata, duration_ms: '2000' } },
    { metadata: { ...metadata, channels: 0 } },
    { metadata: { ...metadata, channels: 3 } },
    { metadata: { ...metadata, channels: '1' } },
    { metadata: {} },
  ])(
    'preserves playback and declines optional visualization outside the memory bounds: %j',
    async overrides => {
      const wrapper = fixture(overrides);
      const pause = vi.spyOn(wrapper.props('media'), 'pause');
      await flushPromises();
      expect(WaveSurfer.create).not.toHaveBeenCalled();
      expect(wrapper.attributes('data-audio-waveform')).toBe('LIMIT');
      expect(wrapper.get('[role="status"]').text()).toBe(
        'JRC_CONTACT_CENTER.AUDIO_WAVEFORM.LIMIT'
      );
      expect(wrapper.props('media').src).toBe('blob:SYNTHETIC-verified');
      expect(pause).not.toHaveBeenCalled();
    }
  );

  it.each(['', 'https://example.invalid/private.wav', '/api/private.wav'])(
    'never fetches a non-blob locator: %s',
    async url => {
      fixture({ url });
      await flushPromises();
      expect(WaveSurfer.create).not.toHaveBeenCalled();
    }
  );

  it('waits for the native player and accepts the exact visualization bounds', async () => {
    const wrapper = fixture({
      media: null,
      byteSize: 20 * 1024 * 1024,
      metadata: { duration_ms: 600000, channels: 2 },
    });
    await flushPromises();
    expect(WaveSurfer.create).not.toHaveBeenCalled();
    await wrapper.setProps({ media: document.createElement('audio') });
    await flushPromises();
    expect(WaveSurfer.create).toHaveBeenCalledOnce();
  });

  it.each([
    null,
    { length: 0 },
    { length: 16000, duration: 601 },
    { length: 16000, numberOfChannels: 3 },
  ])(
    'does not mark missing or excessive decoded media ready: %j',
    async decoded => {
      const wrapper = fixture();
      await flushPromises();
      surfaces[0].getDecodedData.mockReturnValue(decoded);
      surfaces[0].handlers.redrawcomplete();
      await flushPromises();
      expect(wrapper.attributes('data-audio-waveform')).toBe('ERROR');
      expect(wrapper.attributes('data-decoded-samples')).toBe('0');
      expect(wrapper.get('[role="status"]').text()).toBe(
        'JRC_CONTACT_CENTER.AUDIO_WAVEFORM.ERROR'
      );
    }
  );

  it('keeps the native source and controls on decode failure and does not expose library errors', async () => {
    const wrapper = fixture();
    await flushPromises();
    surfaces[0].handlers.error(new Error('SYNTHETIC private library error'));
    await flushPromises();
    expect(wrapper.attributes('data-audio-waveform')).toBe('ERROR');
    expect(wrapper.text()).not.toContain('SYNTHETIC private');
    expect(wrapper.props('media').src).toBe('blob:SYNTHETIC-verified');
    expect(surfaces[0].destroy).not.toHaveBeenCalled();
  });

  it('handles synchronous construction failure without removing the native player', async () => {
    WaveSurfer.create.mockImplementationOnce(() => {
      throw new Error('SYNTHETIC constructor');
    });
    const wrapper = fixture();
    await flushPromises();
    expect(wrapper.attributes('data-audio-waveform')).toBe('ERROR');
    expect(wrapper.props('media').src).toBe('blob:SYNTHETIC-verified');
  });

  it('clears and destroys the old renderer and ignores late decode or error after a version/context replacement', async () => {
    const wrapper = fixture();
    await flushPromises();
    const old = surfaces[0];
    await wrapper.setProps({ url: 'blob:SYNTHETIC-next-verified' });
    await flushPromises();
    expect(old.destroy).toHaveBeenCalledOnce();
    expect(wrapper.attributes('data-audio-waveform')).toBe('LOADING');
    old.handlers.redrawcomplete();
    old.handlers.error();
    await flushPromises();
    expect(wrapper.attributes('data-audio-waveform')).toBe('LOADING');
    expect(wrapper.attributes('data-decoded-samples')).toBe('0');
    surfaces[1].handlers.redrawcomplete();
    await flushPromises();
    expect(wrapper.attributes('data-audio-waveform')).toBe('READY');
  });

  it('disposes the renderer on close/revocation and unmount, with no retained visible waveform', async () => {
    const wrapper = fixture();
    await flushPromises();
    await wrapper.setProps({ url: '' });
    await flushPromises();
    expect(surfaces[0].destroy).toHaveBeenCalledOnce();
    expect(wrapper.attributes('data-decoded-samples')).toBe('0');
    await wrapper.setProps({ url: 'blob:SYNTHETIC-reopened' });
    await flushPromises();
    const current = surfaces[1];
    wrapper.unmount();
    expect(current.destroy).toHaveBeenCalledOnce();
    current.handlers.redrawcomplete();
    current.handlers.error();
    expect(WaveSurfer.create).toHaveBeenCalledTimes(2);
  });
});
