import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import { remuxWebmToOgg } from 'dashboard/components/widgets/WootWriter/utils/webmOpusToOgg';
import { useInstitutionalAudioCapture } from './useInstitutionalAudioCapture';

vi.mock('dashboard/components/widgets/WootWriter/utils/webmOpusToOgg', () => ({
  remuxWebmToOgg: vi.fn(),
}));
let recorders;
let stopTrack;
let microphone;
let permission;
let context;
let limit;
let getUserMedia;
class SyntheticRecorder {
  static isTypeSupported = type => type === 'audio/webm;codecs=opus';

  constructor(stream, options) {
    this.stream = stream;
    this.mimeType = options.mimeType;
    this.state = 'inactive';
    this.start = vi.fn(() => {
      this.state = 'recording';
    });
    this.stop = vi.fn(() => {
      this.state = 'inactive';
      queueMicrotask(() => this.onstop?.());
    });
    recorders.push(this);
  }
}
const setup = () => {
  let capture;
  const wrapper = mount(
    defineComponent({
      setup() {
        capture = useInstitutionalAudioCapture({
          contextKey: computed(() => context.value),
          canCapture: computed(() => permission.value),
          maxBytes: computed(() => limit.value),
        });
        return () => null;
      },
    })
  );
  return { capture, wrapper };
};
const chunk = (value = 'SYNTHETIC encoded bytes') =>
  recorders.at(-1).ondataavailable({ data: new Blob([value]) });
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  })
);
beforeEach(() => {
  vi.resetAllMocks();
  recorders = [];
  stopTrack = vi.fn();
  microphone = { getTracks: () => [{ stop: stopTrack }] };
  permission = ref(true);
  context = ref('SYNTHETIC account1/unit10/profileA');
  limit = ref(1000);
  getUserMedia = vi.fn().mockResolvedValue(microphone);
  vi.stubGlobal('navigator', { mediaDevices: { getUserMedia } });
  vi.stubGlobal('MediaRecorder', SyntheticRecorder);
  vi.spyOn(SyntheticRecorder, 'isTypeSupported').mockImplementation(
    type => type === 'audio/webm;codecs=opus'
  );
  remuxWebmToOgg.mockResolvedValue(
    new Blob(['SYNTHETIC ogg'], { type: 'audio/ogg' })
  );
});

describe('institutional recording lifecycle (synthetic device/transport fixtures, not codec or hardware proof)', () => {
  it('requests no microphone on mount and captures only after explicit start, stopping owned tracks before conversion', async () => {
    const { capture } = setup();
    expect(getUserMedia).not.toHaveBeenCalled();
    await capture.start();
    expect(getUserMedia).toHaveBeenCalledWith({ audio: true, video: false });
    expect(capture.phase.value).toBe('recording');
    chunk();
    capture.stop();
    await flushPromises();
    expect(stopTrack).toHaveBeenCalledOnce();
    expect(remuxWebmToOgg).toHaveBeenCalledOnce();
    expect(capture.phase.value).toBe('ready');
    expect(capture.file.value).toBeInstanceOf(File);
    expect(capture.file.value.name).toBe('gravacao-institucional.ogg');
    expect(capture.file.value.type).toBe('audio/ogg');
  });

  it('does not request duplicate permissions or recorders while a request is pending', async () => {
    let finish;
    getUserMedia.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { capture } = setup();
    const first = capture.start();
    await capture.start();
    expect(getUserMedia).toHaveBeenCalledOnce();
    finish(microphone);
    await first;
    expect(recorders).toHaveLength(1);
  });

  it.each(['cancel', 'context', 'permission', 'unmount'])(
    'stops a late owned stream after %s without creating a recorder',
    async change => {
      let finish;
      getUserMedia.mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      );
      const { capture, wrapper } = setup();
      const pending = capture.start();
      if (change === 'cancel') capture.reset();
      if (change === 'context')
        context.value = 'SYNTHETIC account2/unit20/profileB';
      if (change === 'permission') permission.value = false;
      if (change === 'unmount') wrapper.unmount();
      await flushPromises();
      finish(microphone);
      await pending;
      expect(stopTrack).toHaveBeenCalledOnce();
      expect(recorders).toHaveLength(0);
      expect(capture.file.value).toBeNull();
    }
  );

  it('reports rejected microphone permission without retaining data or starting a recorder', async () => {
    getUserMedia.mockRejectedValueOnce({ name: 'NotAllowedError' });
    const { capture } = setup();
    await capture.start();
    expect(capture.error.value).toBe('CAPTURE_DENIED');
    expect(capture.phase.value).toBe('error');
    expect(recorders).toHaveLength(0);
    expect(capture.file.value).toBeNull();
  });

  it('does not request unsupported microphone formats or access after permission was withdrawn', async () => {
    SyntheticRecorder.isTypeSupported.mockReturnValue(false);
    const { capture } = setup();
    await capture.start();
    expect(capture.error.value).toBe('CAPTURE_UNSUPPORTED');
    expect(getUserMedia).not.toHaveBeenCalled();
    permission.value = false;
    await flushPromises();
    await capture.start();
    expect(getUserMedia).not.toHaveBeenCalled();
  });

  it('stops owned resources on a recorder error and keeps no partial file', async () => {
    const { capture } = setup();
    await capture.start();
    chunk();
    recorders[0].onerror();
    await flushPromises();
    expect(stopTrack).toHaveBeenCalledOnce();
    expect(capture.error.value).toBe('CAPTURE_ERROR');
    expect(capture.file.value).toBeNull();
    expect(remuxWebmToOgg).not.toHaveBeenCalled();
  });

  it('discards over-limit chunks, ends only its own recording and never offers a partial file', async () => {
    limit.value = 10;
    const { capture } = setup();
    await capture.start();
    chunk('123456');
    chunk('123456');
    await flushPromises();
    expect(capture.error.value).toBe('INVALID_CAPTURE');
    expect(stopTrack).toHaveBeenCalledOnce();
    expect(recorders[0].stop).toHaveBeenCalledOnce();
    expect(capture.file.value).toBeNull();
    expect(remuxWebmToOgg).not.toHaveBeenCalled();
  });

  it('discards delayed conversion after a scope change without restoring a file', async () => {
    let finish;
    remuxWebmToOgg.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { capture } = setup();
    await capture.start();
    chunk();
    capture.stop();
    await flushPromises();
    expect(capture.phase.value).toBe('processing');
    context.value = 'SYNTHETIC account1/unit11/profileA';
    await flushPromises();
    finish(new Blob(['SYNTHETIC ogg'], { type: 'audio/ogg' }));
    await flushPromises();
    expect(capture.phase.value).toBe('idle');
    expect(capture.file.value).toBeNull();
  });

  it.each([new Error('SYNTHETIC remux failure'), null])(
    'preserves an explicit conversion failure or invalid output as an unsaved error',
    async failure => {
      if (failure) remuxWebmToOgg.mockRejectedValueOnce(failure);
      else
        remuxWebmToOgg.mockResolvedValueOnce(
          new Blob([], { type: 'audio/ogg' })
        );
      const { capture } = setup();
      await capture.start();
      chunk();
      capture.stop();
      await flushPromises();
      expect(capture.phase.value).toBe('error');
      expect(capture.file.value).toBeNull();
      expect(stopTrack).toHaveBeenCalledOnce();
    }
  );

  it.each(['audio/ogg;codecs=opus', 'audio/mp4'])(
    'keeps native %s output without decoding or inventing a container',
    async type => {
      SyntheticRecorder.isTypeSupported.mockImplementation(
        value => value === type
      );
      const { capture } = setup();
      await capture.start();
      chunk();
      capture.stop();
      capture.stop();
      await flushPromises();
      expect(capture.phase.value).toBe('ready');
      expect(capture.file.value.type).toBe(type.split(';')[0]);
      expect(remuxWebmToOgg).not.toHaveBeenCalled();
      expect(recorders[0].stop).toHaveBeenCalledOnce();
      capture.reset();
      expect(capture.file.value).toBeNull();
    }
  );
});
