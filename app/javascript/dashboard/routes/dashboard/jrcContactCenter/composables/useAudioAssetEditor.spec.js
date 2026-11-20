import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { computed, defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAudioAssetEditor } from './useAudioAssetEditor';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    audioAsset: vi.fn(),
    receiveAudioAsset: vi.fn(),
    receiveAudioVersion: vi.fn(),
    updateAudioAsset: vi.fn(),
    configurationRecord: vi.fn(),
  },
}));
const source = {
  id: '44',
  unit_id: '10',
  name: 'SYNTHETIC original',
  revision: 'a'.repeat(64),
  folder_id: null,
};
const accepted = () => ({
  data: {
    account_id: '1',
    item: source,
    received_version: {
      id: '90',
      audio_asset_id: '44',
      unit_id: '10',
      number: 1,
      byte_size: 15,
      sha256: 'f'.repeat(64),
    },
  },
});
const fixture = () => {
  const accountId = ref('1');
  const unitId = ref('10');
  const folderId = ref('');
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
          folderId,
          canManage: computed(() => allowed.value),
          maxBytes: ref(100),
          onSaved,
          onDenied,
        });
        return () => h('div');
      },
    })
  );
  editor.dialog.value = { open: vi.fn(), close: vi.fn() };
  const file = new File(['SYNTHETIC bytes'], 'SYNTHETIC.wav', {
    type: 'audio/wav',
  });
  const review = () => {
    editor.reviewedDraft.value = editor.fingerprint();
  };
  return {
    editor,
    accountId,
    unitId,
    folderId,
    allowed,
    onSaved,
    onDenied,
    file,
    review,
  };
};
const choose = (editor, file) =>
  editor.chooseFile({ target: { files: [file] } });
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.audioAsset.mockResolvedValue({ data: { item: source } });
  API.configurationRecord.mockResolvedValue({
    data: { item: { ...source, revision: 'b'.repeat(64) } },
  });
  API.receiveAudioAsset.mockResolvedValue(accepted());
  API.receiveAudioVersion.mockResolvedValue(accepted());
  API.updateAudioAsset.mockResolvedValue(accepted());
});

describe('private institutional audio editor delegates all actual authority to the native APIs', () => {
  it('preserves the fresh root folder rather than silently moving a concurrently reorganized audio back to the old folder', async () => {
    const { editor, folderId } = fixture();
    folderId.value = '22';
    await flushPromises();
    await editor.open('edit', source);
    expect(editor.draft.value.folder_id).toBe('');
    expect(editor.selected.value.id).toBe(source.id);
  });
  it.each([
    ['missing receipt', () => ({ data: {} })],
    [
      'foreign account',
      () => ({ ...accepted(), data: { ...accepted().data, account_id: '2' } }),
    ],
    [
      'wrong unit',
      () => ({
        ...accepted(),
        data: {
          ...accepted().data,
          received_version: {
            ...accepted().data.received_version,
            unit_id: '11',
          },
        },
      }),
    ],
    [
      'wrong byte size',
      () => ({
        ...accepted(),
        data: {
          ...accepted().data,
          received_version: {
            ...accepted().data.received_version,
            byte_size: 14,
          },
        },
      }),
    ],
  ])(
    'preserves private input and refuses silent success on a2xx %s',
    async (_name, response) => {
      const { editor, file, review, onSaved } = fixture();
      API.receiveAudioAsset.mockResolvedValueOnce(response());
      await editor.open('upload');
      editor.draft.value.name = 'SYNTHETIC pending confirmation';
      choose(editor, file);
      review();
      await editor.save();
      expect(editor.error.value).toBe('RECEIPT_ERROR');
      expect(editor.file.value).toBe(file);
      expect(editor.submission.value.get('file')).toBe(file);
      expect(onSaved).not.toHaveBeenCalled();
      expect(API.receiveAudioAsset).toHaveBeenCalledOnce();
    }
  );

  it('unlocks a file explicitly rejected before receipt while retaining its metadata draft', async () => {
    const { editor, file, review } = fixture();
    API.receiveAudioAsset.mockRejectedValueOnce({
      response: {
        status: 422,
        data: { error: 'unsupported_institutional_audio_file' },
      },
    });
    await editor.open('upload');
    editor.draft.value.name = 'SYNTHETIC preserved name';
    choose(editor, file);
    review();
    await editor.save();
    expect(editor.error.value).toBe('INVALID_FILE');
    expect(editor.file.value).toBeNull();
    expect(editor.submission.value).toBeNull();
    expect(editor.draft.value.name).toBe('SYNTHETIC preserved name');
  });
  it('sends the current unit, reviewed metadata and actual File as multipart without setting a storage locator', async () => {
    const { editor, file, review, onSaved } = fixture();
    await editor.open('upload');
    editor.draft.value.name = 'SYNTHETIC new';
    choose(editor, file);
    review();
    await editor.save();
    const [account, body] = API.receiveAudioAsset.mock.calls[0];
    expect(account).toBe('1');
    expect(body.get('unit_id')).toBe('10');
    expect(body.get('asset[name]')).toBe('SYNTHETIC new');
    expect(body.get('file')).toBe(file);
    expect(body.has('account_id')).toBe(false);
    expect(body.get('idempotency_key')).toMatch(/^[\w-]{16,100}$/);
    expect(onSaved).toHaveBeenCalledOnce();
  });

  it('requires a nonempty file and explicit review, invalidating that review after a metadata edit', async () => {
    const { editor, file, review } = fixture();
    await editor.open('upload');
    editor.draft.value.name = 'SYNTHETIC new';
    choose(editor, file);
    expect(editor.canSave.value).toBe(false);
    review();
    expect(editor.canSave.value).toBe(true);
    editor.draft.value.name = 'SYNTHETIC changed';
    expect(editor.canSave.value).toBe(false);
    await editor.save();
    expect(API.receiveAudioAsset).not.toHaveBeenCalled();
  });

  it('preserves the exact uncertain submission and request key for a deliberate retry instead of creating another upload', async () => {
    const { editor, file, review, onSaved } = fixture();
    API.receiveAudioAsset.mockRejectedValueOnce({ response: { status: 503 } });
    await editor.open('upload');
    editor.draft.value.name = 'SYNTHETIC retry';
    choose(editor, file);
    review();
    await editor.save();
    const original = API.receiveAudioAsset.mock.calls[0][1];
    expect(editor.error.value).toBe('RECEIPT_ERROR');
    expect(editor.file.value).toBe(file);
    expect(onSaved).not.toHaveBeenCalled();
    expect(API.receiveAudioAsset).toHaveBeenCalledOnce();
    review();
    await editor.save();
    expect(API.receiveAudioAsset.mock.calls[1][1]).toBe(original);
    expect(API.receiveAudioAsset.mock.calls[1][1].get('idempotency_key')).toBe(
      original.get('idempotency_key')
    );
  });

  it('does not submit a second copy while the first native request is unresolved', async () => {
    const { editor, file, review } = fixture();
    let resolve;
    API.receiveAudioAsset.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    await editor.open('upload');
    editor.draft.value.name = 'SYNTHETIC once';
    choose(editor, file);
    review();
    const first = editor.save();
    await editor.save();
    expect(API.receiveAudioAsset).toHaveBeenCalledOnce();
    resolve(accepted());
    await first;
  });

  it.each([0, 101])(
    'rejects a file of %i bytes before submission',
    async size => {
      const { editor, review } = fixture();
      await editor.open('upload');
      editor.draft.value.name = 'SYNTHETIC invalid';
      choose(editor, new File(['x'.repeat(size)], 'SYNTHETIC.wav'));
      review();
      expect(editor.error.value).toBe('INVALID_FILE');
      expect(editor.canSave.value).toBe(false);
      await editor.save();
      expect(API.receiveAudioAsset).not.toHaveBeenCalled();
    }
  );

  it('reuses native metadata CAS without uploading a new blob for an ordinary rename', async () => {
    const { editor, review } = fixture();
    await editor.open('edit', source);
    editor.draft.value.name = 'SYNTHETIC renamed';
    review();
    await editor.save();
    expect(API.updateAudioAsset).toHaveBeenCalledWith(
      '1',
      '44',
      expect.objectContaining({ name: 'SYNTHETIC renamed' }),
      { expected_revision: source.revision }
    );
    expect(API.receiveAudioAsset).not.toHaveBeenCalled();
    expect(API.receiveAudioVersion).not.toHaveBeenCalled();
  });

  it('pins the selected native asset and exact reviewed revision for a replacement', async () => {
    const { editor, file, review } = fixture();
    await editor.open('replace', source);
    choose(editor, file);
    review();
    await editor.save();
    const [account, asset, body] = API.receiveAudioVersion.mock.calls[0];
    expect([account, asset]).toEqual(['1', '44']);
    expect(body.get('expected_revision')).toBe(source.revision);
    expect(body.get('file')).toBe(file);
    expect(body.has('unit_id')).toBe(false);
    expect(API.receiveAudioAsset).not.toHaveBeenCalled();
  });

  it('requires a reviewed current CAS after conflict and preserves the same file and request key', async () => {
    const { editor, file, review } = fixture();
    API.receiveAudioVersion.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    await editor.open('replace', source);
    choose(editor, file);
    review();
    await editor.save();
    const key = API.receiveAudioVersion.mock.calls[0][2].get('idempotency_key');
    expect(editor.revision.state.conflict).toBe(true);
    expect(editor.canSave.value).toBe(false);
    await editor.revision.reload();
    editor.revision.review(true);
    review();
    await editor.save();
    expect(
      API.receiveAudioVersion.mock.calls[1][2].get('expected_revision')
    ).toBe('b'.repeat(64));
    expect(
      API.receiveAudioVersion.mock.calls[1][2].get('idempotency_key')
    ).toBe(key);
    expect(API.receiveAudioVersion.mock.calls[1][2].get('file')).toBe(file);
  });

  it.each(['accountId', 'unitId', 'folderId'])(
    'immediately blocks and then forgets private input when %s changes',
    async field => {
      const state = fixture();
      await state.editor.open('upload');
      state.editor.draft.value.name = 'SYNTHETIC old context';
      choose(state.editor, state.file);
      state.review();
      state[field].value = '99';
      expect(state.editor.canSave.value).toBe(false);
      await state.editor.save();
      await flushPromises();
      expect(state.editor.file.value).toBeNull();
      expect(state.editor.draft.value.name).toBe('');
      expect(API.receiveAudioAsset).not.toHaveBeenCalled();
    }
  );

  it('discards a late private details response after the unit has changed', async () => {
    const { editor, unitId } = fixture();
    let resolve;
    API.audioAsset.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const opened = editor.open('edit', source);
    unitId.value = '11';
    await flushPromises();
    resolve({ data: { item: source } });
    await opened;
    expect(editor.selected.value).toBeNull();
    expect(editor.draft.value.name).toBe('');
    expect(editor.dialog.value.open).not.toHaveBeenCalled();
  });

  it('forgets the file and revision when configuration eligibility is withdrawn', async () => {
    const { editor, file, review, allowed } = fixture();
    await editor.open('replace', source);
    choose(editor, file);
    review();
    allowed.value = false;
    expect(editor.canSave.value).toBe(false);
    await flushPromises();
    expect(editor.file.value).toBeNull();
    expect(editor.revision.state.expected).toBe('');
  });

  it.each([
    'institutional_audio_invalid_codec',
    'institutional_audio_unsafe_file',
    'institutional_audio_integrity_failed',
  ])(
    'allows correction after a definitive native %s rejection without losing the metadata',
    async code => {
      const { editor, file, review, onSaved } = fixture();
      API.receiveAudioAsset.mockRejectedValueOnce({
        response: { status: 422, data: { error: code } },
      });
      await editor.open('upload');
      editor.draft.value.name = 'SYNTHETIC retained metadata';
      choose(editor, file);
      review();
      await editor.save();
      expect(editor.error.value).toBe('INVALID_FILE');
      expect(editor.file.value).toBeNull();
      expect(editor.submission.value).toBeNull();
      expect(editor.draft.value.name).toBe('SYNTHETIC retained metadata');
      expect(onSaved).not.toHaveBeenCalled();
      choose(editor, file);
      review();
      await editor.save();
      expect(onSaved).toHaveBeenCalledOnce();
    }
  );

  it('retains the file after an explicit unavailable-before-persistence response and requires review before retry', async () => {
    const { editor, file, review, onSaved } = fixture();
    API.receiveAudioAsset.mockRejectedValueOnce({
      response: {
        status: 503,
        data: { error: 'institutional_audio_inspection_unavailable' },
      },
    });
    await editor.open('upload');
    editor.draft.value.name = 'SYNTHETIC preserved';
    choose(editor, file);
    review();
    await editor.save();
    const priorKey =
      API.receiveAudioAsset.mock.calls[0][1].get('idempotency_key');
    expect(editor.error.value).toBe('INSPECTION_UNAVAILABLE');
    expect(editor.file.value).toBe(file);
    expect(editor.submission.value).toBeNull();
    expect(editor.canSave.value).toBe(false);
    review();
    await editor.save();
    expect(API.receiveAudioAsset.mock.calls[1][1].get('idempotency_key')).toBe(
      priorKey
    );
    expect(onSaved).toHaveBeenCalledOnce();
  });
});
