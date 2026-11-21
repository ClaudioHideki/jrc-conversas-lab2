import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useSelectedAudioMove } from './useSelectedAudioMove';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    audioAsset: vi.fn(),
    audioUsages: vi.fn(),
    moveAudioAssets: vi.fn(),
  },
}));
const selected = () => ({
  assetId: '9223372036854775806',
  versionId: '9223372036854775807',
  revision: 'a'.repeat(64),
  sha256: 'b'.repeat(64),
  name: 'SYNTHETIC selected',
});
const source = () => ({
  id: selected().assetId,
  unit_id: '10',
  folder_id: null,
  name: selected().name,
  revision: selected().revision,
  latest_version: { id: selected().versionId, sha256: selected().sha256 },
});
const receipt = (folder = null) => ({
  data: {
    account_id: '1',
    items: [{ ...source(), folder_id: folder, revision: 'c'.repeat(64) }],
  },
});
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((done, fail) => {
    resolve = done;
    reject = fail;
  });
  return { promise, resolve, reject };
};
const fixture = () => {
  const accountId = ref('1');
  const unitId = ref('10');
  const canManage = ref(true);
  const contextKey = ref('SYNTHETIC actor profile');
  const selection = ref([selected()]);
  const onDenied = vi.fn();
  const onSaved = vi.fn();
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useSelectedAudioMove({
          accountId,
          unitId,
          canManage,
          contextKey,
          selection,
          onDenied,
          onSaved,
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
    selection,
    onDenied,
    onSaved,
  };
};
enableAutoUnmount(cleanup =>
  afterEach(() => {
    cleanup();
    vi.restoreAllMocks();
  })
);
beforeEach(() => {
  vi.clearAllMocks();
  API.audioAsset.mockResolvedValue({
    data: { account_id: '1', item: source() },
  });
  API.audioUsages.mockResolvedValue({
    data: {
      account_id: '1',
      unit_id: '10',
      audio_asset_id: selected().assetId,
      coverage: 'current_local_ivr_drafts_only',
      provider_configuration_verified: false,
      meta: { total: 1 },
    },
  });
  API.moveAudioAssets.mockResolvedValue(receipt());
});

describe('selected audio metadata movement (mocked transport, not native transaction proof)', () => {
  it('requires fresh source metadata, local reference check and explicit review before moving', async () => {
    const { state, onSaved } = fixture();
    await state.save();
    expect(API.moveAudioAssets).not.toHaveBeenCalled();
    await state.open();
    expect(state.verified.value).toBe(true);
    expect(state.usages.value).toEqual({ [selected().assetId]: 1 });
    expect(state.canSave.value).toBe(false);
    state.reviewed.value = true;
    await state.save();
    expect(API.moveAudioAssets).toHaveBeenCalledExactlyOnceWith('1', {
      unit_id: '10',
      folder_id: null,
      items: [
        {
          audio_asset_id: selected().assetId,
          expected_revision: selected().revision,
        },
      ],
    });
    expect(onSaved).toHaveBeenCalledExactlyOnceWith(receipt().data.items);
  });

  it('requires valid reviewed revisions and bounds the selected count without trusting identifiers', () => {
    const { state, selection, canManage } = fixture();
    selection.value = [];
    expect(state.canOpen.value).toBe(false);
    selection.value = [{ ...selected(), revision: undefined }];
    expect(state.canOpen.value).toBe(false);
    selection.value = Array.from({ length: 21 }, () => selected());
    expect(state.canOpen.value).toBe(false);
    selection.value = [selected()];
    canManage.value = false;
    expect(state.canOpen.value).toBe(false);
  });

  it('invalidates confirmation when the destination changes or its picker is loading', async () => {
    const { state } = fixture();
    await state.open();
    state.reviewed.value = true;
    state.folderId.value = '20';
    expect(state.reviewed.value).toBe(false);
    state.reviewed.value = true;
    state.folderLoading.value = true;
    expect(state.canSave.value).toBe(false);
    state.folderLoading.value = false;
    API.moveAudioAssets.mockResolvedValue(receipt('20'));
    await state.save();
    expect(API.moveAudioAssets.mock.calls[0][1].folder_id).toBe('20');
  });

  it('deduplicates double confirmation while the first request is pending', async () => {
    const { state } = fixture();
    await state.open();
    state.reviewed.value = true;
    const pending = deferred();
    API.moveAudioAssets.mockReturnValue(pending.promise);
    const first = state.save();
    await state.save();
    expect(API.moveAudioAssets).toHaveBeenCalledOnce();
    pending.resolve(receipt());
    await first;
  });

  it('preserves selection and destination after an unknown failure without automatically repeating the write', async () => {
    const { state } = fixture();
    await state.open();
    state.folderId.value = '20';
    state.reviewed.value = true;
    API.moveAudioAssets.mockRejectedValue(
      new Error('SYNTHETIC network interruption')
    );
    await state.save();
    expect(state.items.value[0].assetId).toBe(selected().assetId);
    expect(state.folderId.value).toBe('20');
    expect(state.verified.value).toBe(false);
    expect(state.error.value).toBe('ERROR');
    await state.save();
    expect(API.moveAudioAssets).toHaveBeenCalledOnce();
  });

  it('requires fresh review after a real revision conflict', async () => {
    const { state, onSaved } = fixture();
    await state.open();
    state.reviewed.value = true;
    API.moveAudioAssets.mockRejectedValue({ response: { status: 409 } });
    await state.save();
    expect(state.error.value).toBe('SOURCE_CHANGED');
    expect(state.canSave.value).toBe(false);
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('blocks a source whose revision changed before popup review', async () => {
    const { state } = fixture();
    API.audioAsset.mockResolvedValue({
      data: {
        account_id: '1',
        item: { ...source(), revision: 'f'.repeat(64) },
      },
    });
    await state.open();
    expect(state.error.value).toBe('SOURCE_CHANGED');
    expect(API.audioUsages).not.toHaveBeenCalled();
    expect(state.canSave.value).toBe(false);
  });

  it('does not accept another account or unit in the current metadata response', async () => {
    const { state } = fixture();
    API.audioAsset.mockResolvedValue({
      data: { account_id: '2', item: { ...source(), unit_id: '11' } },
    });
    await state.open();
    expect(state.verified.value).toBe(false);
    expect(state.error.value).toBe('SOURCE_CHANGED');
  });

  it('does not accept a local reference check as proof of provider publication', async () => {
    const { state } = fixture();
    API.audioUsages.mockResolvedValue({
      data: {
        account_id: '1',
        unit_id: '10',
        audio_asset_id: selected().assetId,
        coverage: 'all_provider_configuration',
        provider_configuration_verified: true,
        meta: { total: 0 },
      },
    });
    await state.open();
    expect(state.error.value).toBe('ERROR');
    expect(state.canSave.value).toBe(false);
  });

  it('withholds a success receipt with a different destination or altered version', async () => {
    const { state, onSaved } = fixture();
    await state.open();
    state.reviewed.value = true;
    const invalid = receipt('999');
    invalid.data.items[0].latest_version.id = '123';
    API.moveAudioAssets.mockResolvedValue(invalid);
    await state.save();
    expect(state.error.value).toBe('ERROR');
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('withholds duplicate, incomplete or wrong-account receipts', async () => {
    const { state, onSaved } = fixture();
    await state.open();
    state.reviewed.value = true;
    const invalid = receipt();
    invalid.data.account_id = '2';
    invalid.data.items.push(invalid.data.items[0]);
    API.moveAudioAssets.mockResolvedValue(invalid);
    await state.save();
    expect(state.error.value).toBe('ERROR');
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('clears private review after account, unit, profile, permission or selection changes', async () => {
    const { state, accountId, unitId, contextKey, canManage, selection } =
      fixture();
    await state.open();
    [
      [accountId, '2'],
      [unitId, '11'],
      [contextKey, 'SYNTHETIC changed profile'],
      [canManage, false],
      [selection, []],
    ].forEach(([field, value]) => {
      state.items.value = [selected()];
      state.reviewed.value = true;
      field.value = value;
      expect(state.items.value).toEqual([]);
      expect(state.reviewed.value).toBe(false);
    });
  });

  it('ignores late source metadata after a profile change', async () => {
    const { state, contextKey } = fixture();
    const pending = deferred();
    API.audioAsset.mockReturnValue(pending.promise);
    const opening = state.open();
    await flushPromises();
    contextKey.value = 'SYNTHETIC restricted profile';
    pending.resolve({ data: { account_id: '1', item: source() } });
    await opening;
    expect(state.items.value).toEqual([]);
    expect(state.verified.value).toBe(false);
    expect(API.audioUsages).not.toHaveBeenCalled();
  });

  it('ignores a late persisted response after unit change instead of publishing it into another scope', async () => {
    const { state, unitId, onSaved } = fixture();
    await state.open();
    state.reviewed.value = true;
    const pending = deferred();
    API.moveAudioAssets.mockReturnValue(pending.promise);
    const saving = state.save();
    unitId.value = '11';
    pending.resolve(receipt());
    await saving;
    expect(state.items.value).toEqual([]);
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('denies and forgets private review after the native endpoint rejects the actor', async () => {
    const { state, onDenied, onSaved } = fixture();
    await state.open();
    state.reviewed.value = true;
    API.moveAudioAssets.mockRejectedValue({ response: { status: 401 } });
    await state.save();
    expect(onDenied).toHaveBeenCalledOnce();
    expect(state.items.value).toEqual([]);
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('cancels private pending state when the component unmounts', async () => {
    const { state, wrapper } = fixture();
    await state.open();
    wrapper.unmount();
    expect(state.items.value).toEqual([]);
    expect(state.verified.value).toBe(false);
  });
});
