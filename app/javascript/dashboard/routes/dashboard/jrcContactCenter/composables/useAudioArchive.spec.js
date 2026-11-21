import { createHash, webcrypto } from 'node:crypto';
import { TextEncoder } from 'node:util';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAudioArchive } from './useAudioArchive';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioAsset: vi.fn(), audioArchive: vi.fn(), audioUsages: vi.fn() },
}));
const source = () => ({
  id: '9223372036854775806',
  unit_id: '10',
  name: 'SYNTHETIC selected audio',
  latest_version: {
    id: '9223372036854775807',
    number: 1,
    sha256: 'a'.repeat(64),
    byte_size: 3,
    technical_verification: { id: '100', ready: true },
  },
});
const request = () => [
  {
    audio_asset_id: source().id,
    audio_version_id: source().latest_version.id,
    inspection_id: '100',
    sha256: 'a'.repeat(64),
  },
];
const response = () => {
  const blob = new Blob(['ABC'], { type: 'application/zip' });
  blob.arrayBuffer = async () => new Uint8Array([65, 66, 67]).buffer;
  return {
    data: blob,
    headers: {
      'x-jrc-audio-account': '1',
      'x-jrc-audio-unit': '10',
      'x-jrc-audio-count': '1',
      'x-jrc-audio-bytes': '3',
      'x-jrc-audio-selection': createHash('sha256')
        .update(JSON.stringify(request()))
        .digest('hex'),
      'x-jrc-audio-sha256': createHash('sha256').update('ABC').digest('hex'),
    },
  };
};
const fixture = () => {
  const accountId = ref('1');
  const unitId = ref('10');
  const canManage = ref(true);
  const contextKey = ref('SYNTHETIC original actor profile');
  const limits = ref({ max_entries: 2, max_bytes: 6 });
  const onDenied = vi.fn();
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useAudioArchive({
          accountId,
          unitId,
          canManage,
          contextKey,
          limits,
          onDenied,
        });
        return () => null;
      },
    })
  );
  state.dialog.value = { open: vi.fn(), close: vi.fn() };
  return {
    state,
    wrapper,
    accountId,
    unitId,
    canManage,
    contextKey,
    limits,
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
  vi.stubGlobal('crypto', webcrypto);
  vi.stubGlobal('TextEncoder', TextEncoder);
  vi.stubGlobal(
    'URL',
    Object.assign(class extends URL {}, {
      createObjectURL: vi
        .fn()
        .mockReturnValue('blob:SYNTHETIC-private-archive'),
      revokeObjectURL: vi.fn(),
    })
  );
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  API.audioAsset.mockResolvedValue({
    data: { account_id: '1', item: source() },
  });
  API.audioArchive.mockResolvedValue(response());
  API.audioUsages.mockResolvedValue({
    data: {
      account_id: '1',
      unit_id: '10',
      audio_asset_id: source().id,
      coverage: 'current_local_ivr_drafts_only',
      provider_configuration_verified: false,
      meta: { total: 0 },
    },
  });
});

describe('selected private audio archive (transport units, not native ZIP or codec proof)', () => {
  it('selects without reading private bytes and requires fresh metadata plus explicit review before one ZIP request', async () => {
    const { state } = fixture();
    state.toggle(source());
    expect(API.audioAsset).not.toHaveBeenCalled();
    expect(API.audioArchive).not.toHaveBeenCalled();
    await state.download();
    expect(API.audioArchive).not.toHaveBeenCalled();
    await state.open();
    expect(API.audioAsset).toHaveBeenCalledWith('1', source().id);
    expect(API.audioUsages).toHaveBeenCalledWith('1', source().id, {
      page: 1,
      per_page: 1,
    });
    expect(state.usages.value).toEqual({ [source().id]: 0 });
    expect(state.canDownload.value).toBe(false);
    state.reviewed.value = true;
    await state.download();
    expect(API.audioArchive).toHaveBeenCalledExactlyOnceWith('1', request());
    expect(URL.createObjectURL).toHaveBeenCalledOnce();
    expect(HTMLAnchorElement.prototype.click).toHaveBeenCalledOnce();
    expect(state.delivered.value).toBe(true);
  });

  it('bounds selected count and aggregate bytes using native advertised limits and permits explicit deselection', () => {
    const { state, limits } = fixture();
    state.toggle(source());
    const second = { ...source(), id: '42' };
    limits.value = { max_entries: 1, max_bytes: 6 };
    expect(state.selectable(second)).toBe(false);
    limits.value = { max_entries: 2, max_bytes: 5 };
    state.toggle(second);
    expect(state.items.value).toHaveLength(1);
    expect(state.total.value).toBe(3);
    state.toggle(source());
    expect(state.items.value).toHaveLength(0);
    expect(state.admitted.value).toBe(false);
  });

  it('refuses unverified sources and another unit without treating a known ID as authority', () => {
    const { state, canManage } = fixture();
    const unverified = source();
    unverified.latest_version.technical_verification.ready = false;
    state.toggle(unverified);
    state.toggle({ ...source(), unit_id: '20' });
    canManage.value = false;
    state.toggle(source());
    expect(state.items.value).toHaveLength(0);
  });

  it.each([
    'x-jrc-audio-account',
    'x-jrc-audio-unit',
    'x-jrc-audio-selection',
    'x-jrc-audio-count',
    'x-jrc-audio-bytes',
    'x-jrc-audio-sha256',
  ])(
    'withholds download and resets review after a wrong receipt in %s',
    async header => {
      const { state } = fixture();
      state.toggle(source());
      await state.open();
      state.reviewed.value = true;
      const wrong = response();
      wrong.headers[header] = 'SYNTHETIC-wrong';
      API.audioArchive.mockResolvedValue(wrong);
      await state.download();
      expect(state.error.value).toBe('ERROR');
      expect(state.reviewed.value).toBe(false);
      expect(URL.createObjectURL).not.toHaveBeenCalled();
      expect(state.items.value).toHaveLength(1);
    }
  );

  it('rejects a non-ZIP blob even when the remaining response headers are valid', async () => {
    const { state } = fixture();
    state.toggle(source());
    await state.open();
    state.reviewed.value = true;
    const wrong = response();
    wrong.data = new Blob(['ABC'], { type: 'text/html' });
    API.audioArchive.mockResolvedValue(wrong);
    await state.download();
    expect(state.error.value).toBe('ERROR');
    expect(HTMLAnchorElement.prototype.click).not.toHaveBeenCalled();
  });

  it('pins exact source version and proof and requires reselection after a metadata change', async () => {
    const { state } = fixture();
    state.toggle(source());
    state.toggle({
      ...source(),
      id: '42',
      latest_version: { ...source().latest_version, id: '43' },
    });
    const newer = source();
    newer.latest_version.technical_verification.id = '101';
    API.audioAsset.mockResolvedValue({
      data: { account_id: '1', item: newer },
    });
    await state.open();
    state.reviewed.value = true;
    await state.download();
    expect(state.error.value).toBe('SOURCE_CHANGED');
    expect(API.audioArchive).not.toHaveBeenCalled();
    expect(state.items.value[0].inspectionId).toBe('100');
    expect(API.audioAsset).toHaveBeenCalledOnce();
  });

  it('checks selected metadata and local references sequentially without starting the next source before the first completes', async () => {
    const { state } = fixture();
    const second = {
      ...source(),
      id: '42',
      latest_version: { ...source().latest_version, id: '43' },
    };
    state.toggle(source());
    state.toggle(second);
    const steps = [];
    let release;
    API.audioAsset.mockImplementation(async (_, id) => {
      steps.push(`metadata:${id}`);
      if (id === source().id)
        await new Promise(resolve => {
          release = resolve;
        });
      return {
        data: { account_id: '1', item: id === source().id ? source() : second },
      };
    });
    API.audioUsages.mockImplementation(async (_, id) => {
      steps.push(`usages:${id}`);
      return {
        data: {
          account_id: '1',
          unit_id: '10',
          audio_asset_id: id,
          coverage: 'current_local_ivr_drafts_only',
          provider_configuration_verified: false,
          meta: { total: 0 },
        },
      };
    });
    const opening = state.open();
    await vi.waitFor(() => expect(API.audioAsset).toHaveBeenCalledOnce());
    expect(API.audioUsages).not.toHaveBeenCalled();
    release();
    await opening;
    expect(steps).toEqual([
      `metadata:${source().id}`,
      `usages:${source().id}`,
      'metadata:42',
      'usages:42',
    ]);
    expect(state.verified.value).toBe(true);
    expect(state.reviewed.value).toBe(false);
    expect(API.audioArchive).not.toHaveBeenCalled();
  });

  it('requires a genuine authorized local-reference check and never interprets it as verified PABX configuration', async () => {
    const { state } = fixture();
    state.toggle(source());
    API.audioUsages.mockResolvedValue({
      data: {
        account_id: '1',
        unit_id: '20',
        audio_asset_id: source().id,
        coverage: 'current_local_ivr_drafts_only',
        provider_configuration_verified: true,
        meta: { total: 0 },
      },
    });
    await state.open();
    state.reviewed.value = true;
    await state.download();
    expect(state.canDownload.value).toBe(false);
    expect(state.error.value).toBe('ERROR');
    expect(API.audioArchive).not.toHaveBeenCalled();
  });

  it.each(['accountId', 'unitId', 'canManage', 'contextKey'])(
    'discards a late ZIP response and selected private metadata when %s changes',
    async key => {
      let finish;
      const current = fixture();
      current.state.toggle(source());
      await current.state.open();
      current.state.reviewed.value = true;
      API.audioArchive.mockReturnValue(
        new Promise(resolve => {
          finish = resolve;
        })
      );
      const pending = current.state.download();
      await vi.waitFor(() => expect(API.audioArchive).toHaveBeenCalledOnce());
      current[key].value = key === 'canManage' ? false : '2';
      finish(response());
      await pending;
      expect(current.state.items.value).toHaveLength(0);
      expect(URL.createObjectURL).not.toHaveBeenCalled();
    }
  );

  it('does not issue parallel requests on a double confirmation and does not auto retry a failed transport', async () => {
    let reject;
    const { state } = fixture();
    state.toggle(source());
    await state.open();
    state.reviewed.value = true;
    API.audioArchive.mockReturnValue(
      new Promise((_, rejectRequest) => {
        reject = rejectRequest;
      })
    );
    const pending = state.download();
    await vi.waitFor(() => expect(API.audioArchive).toHaveBeenCalledOnce());
    await state.download();
    reject(new Error('SYNTHETIC network failure'));
    await pending;
    expect(API.audioArchive).toHaveBeenCalledOnce();
    expect(state.items.value).toHaveLength(1);
    expect(state.canDownload.value).toBe(false);
  });

  it('clears selection and tells the parent to refresh current authority after an explicit denial', async () => {
    const { state, onDenied } = fixture();
    state.toggle(source());
    API.audioAsset.mockRejectedValue({ response: { status: 403 } });
    await state.open();
    expect(onDenied).toHaveBeenCalledOnce();
    expect(state.items.value).toHaveLength(0);
    expect(API.audioArchive).not.toHaveBeenCalled();
  });

  it('revokes its own temporary download URL on close and unmount without closing user browsers', async () => {
    const { state, wrapper } = fixture();
    state.toggle(source());
    await state.open();
    state.reviewed.value = true;
    await state.download();
    state.close();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith(
      'blob:SYNTHETIC-private-archive'
    );
    expect(state.items.value).toHaveLength(0);
    wrapper.unmount();
    await flushPromises();
    expect(URL.revokeObjectURL).toHaveBeenCalledOnce();
  });
});
