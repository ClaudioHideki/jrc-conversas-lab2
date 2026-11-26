import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { downloadFile } from '@chatwoot/utils';
import Player from 'dashboard/components-next/Calls/CallRecordingPlayer.vue';

vi.mock('@chatwoot/utils', () => ({ downloadFile: vi.fn() }));
vi.mock('dashboard/composables/emitter', () => ({ useEmitter: vi.fn() }));
vi.mock('shared/helpers/mitt', () => ({ emitter: { emit: vi.fn() } }));
const wrappers = [];
const Button = defineComponent({
  props: { label: { type: String, default: '' } },
  emits: ['click'],
  setup(props, { slots, emit }) {
    return () =>
      h('button', { type: 'button', onClick: () => emit('click') }, [
        slots.icon?.(),
        slots.default?.(),
        props.label,
      ]);
  },
});
const fixture = (props = {}) => {
  const wrapper = mount(Player, {
    props: { src: 'blob:synthetic-recording', ...props },
    global: { stubs: { Button, Icon: true } },
  });
  wrappers.push(wrapper);
  return wrapper;
};
beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockResolvedValue();
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => {});
});
afterEach(() => {
  wrappers.splice(0).forEach(wrapper => wrapper.unmount());
  vi.restoreAllMocks();
});

describe('reuse of the native recording player without implicit download authority', () => {
  it('preserves the existing default download control and flow for its current consumers', async () => {
    const wrapper = fixture();
    await wrapper.get('[data-native-recording-download]').trigger('click');
    expect(downloadFile).toHaveBeenCalledWith({
      url: 'blob:synthetic-recording',
      type: 'audio',
    });
  });
  it('removes its local download shortcut when the scoped page uses a separately authorized endpoint', () => {
    const wrapper = fixture({ canDownload: false });
    expect(wrapper.find('[data-native-recording-download]').exists()).toBe(
      false
    );
    expect(wrapper.find('audio').exists()).toBe(true);
    expect(downloadFile).not.toHaveBeenCalled();
  });
  it('reports a native audio failure to the owning scoped page', async () => {
    const wrapper = fixture({ canDownload: false });
    await wrapper.get('audio').trigger('error');
    expect(wrapper.emitted('error')).toHaveLength(1);
    expect(downloadFile).not.toHaveBeenCalled();
  });
  it('handles a rejected play promise without unhandled errors or a false successful playing state', async () => {
    HTMLMediaElement.prototype.play.mockRejectedValueOnce(
      new Error('SYNTHETIC playback unavailable')
    );
    const wrapper = fixture({ canDownload: false });
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('error')).toHaveLength(1);
    expect(downloadFile).not.toHaveBeenCalled();
  });
  it('pauses only its own media element when the scoped selection is unmounted', () => {
    const wrapper = fixture({ canDownload: false });
    wrapper.unmount();
    expect(HTMLMediaElement.prototype.pause).toHaveBeenCalledOnce();
  });
  it('waits for explicit current authorization before starting sound and prevents duplicate pending requests', async () => {
    let resolve;
    const beforePlayback = vi.fn(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const wrapper = fixture({ canDownload: false, beforePlayback });
    await wrapper.get('[data-native-recording-play]').trigger('click');
    await wrapper.get('[data-native-recording-play]').trigger('click');
    expect(beforePlayback).toHaveBeenCalledOnce();
    expect(HTMLMediaElement.prototype.play).not.toHaveBeenCalled();
    resolve(true);
    await flushPromises();
    expect(HTMLMediaElement.prototype.play).toHaveBeenCalledOnce();
    await wrapper.get('[data-native-recording-play]').trigger('click');
    expect(beforePlayback).toHaveBeenCalledOnce();
    expect(HTMLMediaElement.prototype.pause).toHaveBeenCalledOnce();
  });
  it('does not play when the current reproduction audit or authorization is rejected', async () => {
    const beforePlayback = vi.fn().mockResolvedValue(false);
    const wrapper = fixture({ canDownload: false, beforePlayback });
    await wrapper.get('[data-native-recording-play]').trigger('click');
    await flushPromises();
    expect(beforePlayback).toHaveBeenCalledOnce();
    expect(HTMLMediaElement.prototype.play).not.toHaveBeenCalled();
  });
  it('cannot play a removed selection after a delayed authorization response', async () => {
    let resolve;
    const beforePlayback = () =>
      new Promise(done => {
        resolve = done;
      });
    const wrapper = fixture({ canDownload: false, beforePlayback });
    await wrapper.get('[data-native-recording-play]').trigger('click');
    wrapper.unmount();
    resolve(true);
    await flushPromises();
    expect(HTMLMediaElement.prototype.play).not.toHaveBeenCalled();
  });
});
