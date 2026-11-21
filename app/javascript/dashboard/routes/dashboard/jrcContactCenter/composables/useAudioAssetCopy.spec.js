import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAudioAssetEditor } from './useAudioAssetEditor';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    audioAsset: vi.fn(),
    duplicateAudioAsset: vi.fn(),
    configurationRecord: vi.fn(),
    receiveAudioAsset: vi.fn(),
    receiveAudioVersion: vi.fn(),
    updateAudioAsset: vi.fn(),
  },
}));
const original = () => ({
  id: '9007199254740993',
  unit_id: '10',
  name: 'SYNTHETIC source',
  folder_id: null,
  revision: 'a'.repeat(64),
  latest_version: {
    id: '9007199254740995',
    audio_asset_id: '9007199254740993',
    unit_id: '10',
    number: 3,
    source_kind: 'browser_capture',
    byte_size: 60,
    file_name: 'SYNTHETIC.wav',
    sha256: 'f'.repeat(64),
    technical_verification: { ready: true },
  },
});
const accepted = () => ({
  data: {
    account_id: '1',
    item: { id: '9007199254740997', unit_id: '10', revision: 'b'.repeat(64) },
    received_version: {
      id: '9007199254740998',
      audio_asset_id: '9007199254740997',
      unit_id: '10',
      number: 1,
      source_kind: 'browser_capture',
      byte_size: 60,
      sha256: 'f'.repeat(64),
    },
  },
});
const fixture = () => {
  const accountId = ref('1');
  const unitId = ref('10');
  const allowed = ref(true);
  const onSaved = vi.fn();
  const onDenied = vi.fn();
  let editor;
  mount(
    defineComponent({
      setup() {
        editor = useAudioAssetEditor({
          accountId,
          unitId,
          folderId: ref(''),
          canManage: allowed,
          maxBytes: ref(100),
          onSaved,
          onDenied,
        });
        return () => h('div');
      },
    })
  );
  editor.dialog.value = { open: vi.fn(), close: vi.fn() };
  return {
    editor,
    accountId,
    unitId,
    allowed,
    onSaved,
    onDenied,
    review: () => {
      editor.reviewedDraft.value = editor.fingerprint();
    },
  };
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.audioAsset.mockResolvedValue({ data: { item: original() } });
  API.duplicateAudioAsset.mockResolvedValue(accepted());
  API.configurationRecord.mockResolvedValue({
    data: { item: { ...original(), revision: 'c'.repeat(64) } },
  });
});

describe('copy mode reuses the native institutional audio editor', () => {
  it.each([
    'institutional_audio_not_verified',
    'institutional_audio_inspection_changed',
  ])(
    'blocks the stale source after the definitive native %s refusal while preserving the draft',
    async code => {
      const { editor, review, onSaved } = fixture();
      API.duplicateAudioAsset.mockRejectedValueOnce({
        response: { status: 409, data: { error: code } },
      });
      await editor.open('copy', original());
      editor.draft.value.name = 'SYNTHETIC preserved copy name';
      review();
      await editor.save();
      expect(editor.error.value).toBe('COPY_SOURCE_NOT_READY');
      expect(editor.submission.value).toBeNull();
      expect(editor.draft.value.name).toBe('SYNTHETIC preserved copy name');
      expect(editor.copyVersion.value.id).toBe(original().latest_version.id);
      review();
      expect(editor.canSave.value).toBe(false);
      await editor.save();
      expect(API.duplicateAudioAsset).toHaveBeenCalledOnce();
      expect(onSaved).not.toHaveBeenCalled();
    }
  );

  it('pins the authorized source version and requires review without importing or recording another file', async () => {
    const { editor, review, onSaved } = fixture();
    await editor.open('copy', original());
    expect(editor.canSave.value).toBe(false);
    expect(editor.file.value).toBeNull();
    expect(Object.isFrozen(editor.copyVersion.value)).toBe(true);
    editor.draft.value.name = 'SYNTHETIC reviewed copy';
    review();
    expect(editor.canSave.value).toBe(true);
    await editor.save();
    expect(API.duplicateAudioAsset).toHaveBeenCalledWith('1', original().id, {
      asset: {
        name: 'SYNTHETIC reviewed copy',
        description: '',
        purpose: '',
        folder_id: '',
      },
      source_version_id: original().latest_version.id,
      expected_revision: 'a'.repeat(64),
      idempotency_key: expect.any(String),
    });
    expect(API.receiveAudioAsset).not.toHaveBeenCalled();
    expect(API.receiveAudioVersion).not.toHaveBeenCalled();
    expect(onSaved).toHaveBeenCalledOnce();
    expect(onSaved).toHaveBeenCalledWith(accepted().data.item);
    expect(editor.copyVersion.value).toBeNull();
  });

  it.each([
    { technical_verification: { ready: false } },
    { technical_verification: null },
    { unit_id: '11' },
    { audio_asset_id: '999' },
    { byte_size: 101 },
  ])(
    'refuses an unusable or cross-context source snapshot %j before opening the editor',
    async patch => {
      const { editor } = fixture();
      const row = original();
      Object.assign(row.latest_version, patch);
      API.audioAsset.mockResolvedValueOnce({ data: { item: row } });
      await editor.open('copy', row);
      expect(editor.dialog.value.open).not.toHaveBeenCalled();
      expect(editor.canSave.value).toBe(false);
      expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
    }
  );

  it('reuses the exact frozen intention and UUID after an unknown network result', async () => {
    const { editor, review, onSaved } = fixture();
    API.duplicateAudioAsset.mockRejectedValueOnce(
      new Error('SYNTHETIC lost response')
    );
    await editor.open('copy', original());
    review();
    await editor.save();
    const first = API.duplicateAudioAsset.mock.calls[0][2];
    expect(editor.error.value).toBe('RECEIPT_ERROR');
    expect(Object.isFrozen(editor.submission.value.asset)).toBe(true);
    expect(editor.canSave.value).toBe(false);
    review();
    await editor.save();
    expect(API.duplicateAudioAsset.mock.calls[1][2]).toEqual(first);
    expect(onSaved).toHaveBeenCalledOnce();
  });

  it('does not silently repin to a newer source version during conflict review', async () => {
    const { editor, review } = fixture();
    API.duplicateAudioAsset.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    await editor.open('copy', original());
    review();
    await editor.save();
    expect(editor.revision.state.conflict).toBe(true);
    await editor.revision.reload();
    expect(editor.canSave.value).toBe(false);
    editor.revision.review(true);
    review();
    await editor.save();
    expect(API.duplicateAudioAsset.mock.calls[1][2]).toMatchObject({
      source_version_id: original().latest_version.id,
      expected_revision: 'c'.repeat(64),
      idempotency_key: API.duplicateAudioAsset.mock.calls[0][2].idempotency_key,
    });
  });

  it.each(['account_id', 'old_identity', 'digest', 'size', 'version'])(
    'refuses a divergent %s receipt while preserving the intention',
    async field => {
      const { editor, review, onSaved } = fixture();
      const result = accepted();
      if (field === 'account_id') result.data.account_id = '2';
      if (field === 'old_identity') result.data.item.id = original().id;
      if (field === 'digest')
        result.data.received_version.sha256 = 'e'.repeat(64);
      if (field === 'size') result.data.received_version.byte_size = 61;
      if (field === 'version') result.data.received_version.number = 2;
      API.duplicateAudioAsset.mockResolvedValueOnce(result);
      await editor.open('copy', original());
      review();
      await editor.save();
      expect(onSaved).not.toHaveBeenCalled();
      expect(editor.error.value).toBe('RECEIPT_ERROR');
      expect(editor.copyVersion.value.id).toBe(original().latest_version.id);
      expect(editor.submission.value).not.toBeNull();
    }
  );

  it('prevents double-clicks while the one native copy is in flight', async () => {
    const { editor, review } = fixture();
    let finish;
    API.duplicateAudioAsset.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await editor.open('copy', original());
    review();
    const first = editor.save();
    await editor.save();
    expect(API.duplicateAudioAsset).toHaveBeenCalledOnce();
    finish(accepted());
    await first;
  });

  it('forgets private metadata on a unit change and ignores a late source response', async () => {
    const { editor, unitId } = fixture();
    let finish;
    API.audioAsset.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const opening = editor.open('copy', original());
    unitId.value = '11';
    await flushPromises();
    finish({ data: { item: original() } });
    await opening;
    expect(editor.dialog.value.open).not.toHaveBeenCalled();
    expect(editor.copyVersion.value).toBeNull();
  });

  it('clears the copy and withholds success after a profile withdrawal while the response is in flight', async () => {
    const { editor, allowed, review, onSaved } = fixture();
    let finish;
    API.duplicateAudioAsset.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    await editor.open('copy', original());
    review();
    const saving = editor.save();
    allowed.value = false;
    await flushPromises();
    finish(accepted());
    await saving;
    expect(editor.copyVersion.value).toBeNull();
    expect(editor.submission.value).toBeNull();
    expect(onSaved).not.toHaveBeenCalled();
  });
});
