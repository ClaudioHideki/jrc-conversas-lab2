import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAudioBytes } from './useAudioBytes';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioBytes: vi.fn() },
}));
const versionValue = {
  id: '99',
  unit_id: '10',
  sha256: 'a'.repeat(64),
  byte_size: 3,
  content_type: 'audio/wav',
  file_name: 'SYNTHETIC.wav',
};
const response = () => {
  const blob = new Blob(['ABC'], { type: 'audio/wav' });
  blob.arrayBuffer = async () => new Uint8Array([65, 66, 67]).buffer;
  return {
    data: blob,
    headers: {
      'x-jrc-audio-account': '1',
      'x-jrc-audio-unit': '10',
      'x-jrc-audio-version': '99',
      'x-jrc-audio-inspection': '100',
      'x-jrc-audio-sha256': versionValue.sha256,
    },
  };
};
const fixture = () => {
  const accountId = ref('1');
  const assetId = ref('44');
  const version = ref({ ...versionValue });
  const inspectionId = ref('100');
  const canManage = ref(true);
  const onDenied = vi.fn();
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useAudioBytes({
          accountId,
          assetId,
          version,
          inspectionId,
          canManage,
          onDenied,
        });
        return () => null;
      },
    })
  );
  return {
    state,
    wrapper,
    accountId,
    assetId,
    version,
    inspectionId,
    canManage,
    onDenied,
  };
};
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  })
);
beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal('crypto', {
    subtle: {
      digest: vi.fn().mockResolvedValue(new Uint8Array(32).fill(170).buffer),
    },
  });
  vi.stubGlobal(
    'URL',
    Object.assign(class extends URL {}, {
      createObjectURL: vi.fn().mockReturnValue('blob:SYNTHETIC-private-bytes'),
      revokeObjectURL: vi.fn(),
    })
  );
  API.audioBytes.mockResolvedValue(response());
});

describe('authenticated audio byte lifecycle (transport fixtures, not native codec proof)', () => {
  it('opens only deliberately requested exact bytes after validating scope, observation and SHA-256', async () => {
    const { state } = fixture();
    expect(API.audioBytes).not.toHaveBeenCalled();
    await state.open();
    expect(API.audioBytes).toHaveBeenCalledWith('1', '44', '99');
    expect(crypto.subtle.digest).toHaveBeenCalledWith(
      'SHA-256',
      new Uint8Array([65, 66, 67]).buffer
    );
    expect(state.url.value).toBe('blob:SYNTHETIC-private-bytes');
    expect(URL.createObjectURL).toHaveBeenCalledOnce();
  });

  it.each([
    'x-jrc-audio-account',
    'x-jrc-audio-unit',
    'x-jrc-audio-version',
    'x-jrc-audio-inspection',
    'x-jrc-audio-sha256',
  ])(
    'withholds bytes when the server returns another exact identity in %s',
    async header => {
      const wrong = response();
      wrong.headers[header] = 'SYNTHETIC-wrong';
      API.audioBytes.mockResolvedValue(wrong);
      const { state } = fixture();
      await state.open();
      expect(state.error.value).toBe('ERROR');
      expect(URL.createObjectURL).not.toHaveBeenCalled();
    }
  );

  it('does not create a player or download for a corrupt buffer or incorrect size', async () => {
    const { state, version } = fixture();
    crypto.subtle.digest.mockResolvedValueOnce(new Uint8Array(32).buffer);
    await state.open();
    expect(state.error.value).toBe('ERROR');
    version.value = { ...versionValue, byte_size: 4 };
    await state.open();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    expect(state.url.value).toBe('');
  });

  it('accepts MIME parameters for the exact supported media type and rejects a different format', async () => {
    const valid = response();
    valid.data = new Blob(['ABC'], { type: 'audio/wav; charset=binary' });
    valid.data.arrayBuffer = async () => new Uint8Array([65, 66, 67]).buffer;
    API.audioBytes.mockResolvedValueOnce(valid);
    const { state } = fixture();
    await state.open();
    expect(state.url.value).toBe('blob:SYNTHETIC-private-bytes');
    const invalid = response();
    invalid.data = new Blob(['ABC'], { type: 'application/json' });
    API.audioBytes.mockResolvedValueOnce(invalid);
    await state.open();
    expect(state.error.value).toBe('ERROR');
    expect(state.url.value).toBe('');
    expect(URL.createObjectURL).toHaveBeenCalledOnce();
  });

  it('deduplicates pending reads and rejects a late payload after account or version change', async () => {
    let complete;
    API.audioBytes.mockReturnValue(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const { state, accountId } = fixture();
    const first = state.open();
    await state.open();
    expect(API.audioBytes).toHaveBeenCalledOnce();
    accountId.value = '2';
    complete(response());
    await first;
    expect(state.url.value).toBe('');
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  });

  it('rejects a late digest after inspection change and revokes already opened bytes on scope withdrawal', async () => {
    const { state, inspectionId, canManage } = fixture();
    await state.open();
    canManage.value = false;
    expect(state.url.value).toBe('');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:SYNTHETIC-private-bytes'
    );
    canManage.value = true;
    let complete;
    crypto.subtle.digest.mockReturnValueOnce(
      new Promise(resolve => {
        complete = resolve;
      })
    );
    const pending = state.open();
    await flushPromises();
    inspectionId.value = '101';
    complete(new Uint8Array(32).fill(170).buffer);
    await pending;
    expect(state.url.value).toBe('');
    expect(URL.createObjectURL).toHaveBeenCalledTimes(1);
  });

  it.each([401, 403, 404])(
    'clears bytes and delegates %s to native denied handling',
    async status => {
      const { state, onDenied } = fixture();
      await state.open();
      API.audioBytes.mockRejectedValueOnce({ response: { status } });
      await state.open();
      expect(onDenied).toHaveBeenCalledOnce();
      expect(state.url.value).toBe('');
    }
  );

  it('preserves stale-proof and unsupported-player errors without disabling an already verified download', async () => {
    const { state, wrapper } = fixture();
    API.audioBytes.mockRejectedValueOnce({ response: { status: 409 } });
    await state.open();
    expect(state.error.value).toBe('NOT_READY');
    await state.open();
    state.playbackFailed();
    expect(state.error.value).toBe('PLAYBACK_ERROR');
    expect(state.url.value).toBe('blob:SYNTHETIC-private-bytes');
    await state.open();
    wrapper.unmount();
    expect(state.url.value).toBe('');
    expect(URL.revokeObjectURL).toHaveBeenCalledTimes(2);
  });

  it('does not request bytes without current permission and the latest valid observation identity', async () => {
    const { state, inspectionId, canManage } = fixture();
    canManage.value = false;
    await state.open();
    canManage.value = true;
    inspectionId.value = '';
    await state.open();
    expect(API.audioBytes).not.toHaveBeenCalled();
  });

  it('reauthorizes and verifies again before the explicit download rather than using an older preview buffer as a grant', async () => {
    const clicked = vi
      .spyOn(HTMLAnchorElement.prototype, 'click')
      .mockImplementation(() => {});
    const { state, onDenied } = fixture();
    await state.open();
    await state.download();
    expect(API.audioBytes).toHaveBeenCalledTimes(2);
    expect(clicked).toHaveBeenCalledOnce();
    API.audioBytes.mockRejectedValueOnce({ response: { status: 401 } });
    await state.download();
    expect(clicked).toHaveBeenCalledTimes(1);
    expect(onDenied).toHaveBeenCalledOnce();
    expect(state.url.value).toBe('');
  });
});
