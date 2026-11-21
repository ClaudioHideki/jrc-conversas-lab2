import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useSelectedAudioCopies } from './useSelectedAudioCopies';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { audioAsset: vi.fn(), duplicateAudioAsset: vi.fn() },
}));
const selected = (index = 0) => ({
  assetId: String(21 + index),
  versionId: String(121 + index),
  inspectionId: String(221 + index),
  name: `SYNTHETIC source ${index}`,
  revision: 'a'.repeat(64),
  sha256: String(index + 1).repeat(64),
  number: 1,
  byteSize: 60,
});
const source = id => {
  const row = selected(Number(id) - 21);
  return {
    id,
    unit_id: '10',
    name: row.name,
    revision: row.revision,
    description: 'SYNTHETIC description',
    purpose: '',
    latest_version: {
      id: row.versionId,
      number: 1,
      sha256: row.sha256,
      byte_size: row.byteSize,
      source_kind: 'user_upload',
      technical_verification: { id: row.inspectionId, ready: true },
    },
  };
};
const accepted = id => ({
  data: {
    account_id: '1',
    item: {
      id: String(Number(id) + 500),
      unit_id: '10',
      revision: 'b'.repeat(64),
    },
    received_version: {
      id: String(Number(id) + 600),
      audio_asset_id: String(Number(id) + 500),
      unit_id: '10',
      number: 1,
      source_kind: 'user_upload',
      sha256: source(id).latest_version.sha256,
      byte_size: 60,
    },
  },
});
const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
};
const fixture = (rows = [selected(), selected(1)]) => {
  const accountId = ref('1');
  const unitId = ref('10');
  const contextKey = ref('SYNTHETIC profile');
  const canManage = ref(true);
  const admitted = ref(true);
  const selection = ref(rows);
  const onDenied = vi.fn();
  const onSettled = vi.fn();
  let state;
  const wrapper = mount(
    defineComponent({
      setup() {
        state = useSelectedAudioCopies({
          accountId,
          unitId,
          contextKey,
          canManage,
          admitted,
          selection,
          initialFolderId: ref(''),
          onDenied,
          onSettled,
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
    contextKey,
    canManage,
    admitted,
    selection,
    onDenied,
    onSettled,
    review: () => {
      state.folderLoading.value = false;
      state.reviewed.value = true;
    },
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
  API.audioAsset.mockImplementation(async (_account, id) => ({
    data: { account_id: '1', item: source(id) },
  }));
  API.duplicateAudioAsset.mockImplementation(async (_account, id) =>
    accepted(id)
  );
});

describe('sequential selected audio copies (mocked transport, not native or scanner proof)', () => {
  it('requires byte-admitted selection and current configuration authority before reading or copying sources', async () => {
    const { state, admitted, canManage } = fixture();
    admitted.value = false;
    await state.open();
    expect(API.audioAsset).not.toHaveBeenCalled();
    admitted.value = true;
    canManage.value = false;
    await state.open();
    await state.save();
    expect(API.audioAsset).not.toHaveBeenCalled();
    expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
  });

  it('checks both exact authorized sources and requires review before creating independent native copies', async () => {
    const { state, review, onSettled } = fixture();
    await state.open();
    expect(state.verified.value).toBe(true);
    expect(state.canSave.value).toBe(false);
    await state.save();
    expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
    review();
    await state.save();
    expect(API.duplicateAudioAsset.mock.calls.map(row => row[1])).toEqual([
      '21',
      '22',
    ]);
    expect(state.confirmed.value).toHaveLength(2);
    expect(state.complete.value).toBe(true);
    expect(onSettled).not.toHaveBeenCalled();
    state.dismiss();
    expect(onSettled).toHaveBeenCalledWith({
      confirmed: [accepted('21').data, accepted('22').data],
      uncertain: 0,
      blocked: 0,
      pending: 0,
    });
    expect(JSON.stringify(onSettled.mock.calls)).not.toContain(
      'idempotency_key'
    );
  });

  it('executes one native request at a time and ignores a repeated submit while the first one is pending', async () => {
    const gate = deferred();
    API.duplicateAudioAsset.mockImplementationOnce(() => gate.promise);
    const { state, review } = fixture();
    await state.open();
    review();
    const saving = state.save();
    await flushPromises();
    await state.save();
    state.dismiss();
    expect(state.active.value).toBe(true);
    expect(API.duplicateAudioAsset).toHaveBeenCalledOnce();
    gate.resolve(accepted('21'));
    await saving;
    expect(API.duplicateAudioAsset).toHaveBeenCalledTimes(2);
    expect(state.complete.value).toBe(true);
    await state.save();
    expect(API.duplicateAudioAsset).toHaveBeenCalledTimes(2);
  });

  it('keeps a possibly accepted second request frozen and retries only that item with its same idempotency key after explicit review', async () => {
    API.duplicateAudioAsset
      .mockResolvedValueOnce(accepted('21'))
      .mockRejectedValueOnce(new Error('SYNTHETIC timeout'));
    const { state, review } = fixture();
    await state.open();
    review();
    await state.save();
    expect(state.confirmed.value).toHaveLength(1);
    expect(state.uncertain.value).toHaveLength(1);
    expect(state.reviewed.value).toBe(false);
    const previous = API.duplicateAudioAsset.mock.calls[1][2];
    expect(Object.isFrozen(previous)).toBe(true);
    expect(Object.isFrozen(previous.asset)).toBe(true);
    expect(state.locked.value).toBe(true);
    await state.save();
    expect(API.duplicateAudioAsset).toHaveBeenCalledTimes(2);
    review();
    await state.save();
    expect(API.duplicateAudioAsset.mock.calls.map(row => row[1])).toEqual([
      '21',
      '22',
      '22',
    ]);
    expect(API.duplicateAudioAsset.mock.calls[2][2]).toBe(previous);
    expect(state.complete.value).toBe(true);
  });

  it('reports a definitive conflict after a confirmed copy and leaves later items unattempted', async () => {
    API.duplicateAudioAsset
      .mockResolvedValueOnce(accepted('21'))
      .mockRejectedValueOnce({ response: { status: 409 } });
    const { state, review, onSettled } = fixture([
      selected(),
      selected(1),
      selected(2),
    ]);
    await state.open();
    review();
    await state.save();
    expect(state.items.value.map(row => row.status)).toEqual([
      'confirmed',
      'blocked',
      'pending',
    ]);
    expect(API.duplicateAudioAsset).toHaveBeenCalledTimes(2);
    expect(state.error.value).toBe('SOURCE_CHANGED');
    review();
    await state.save();
    expect(API.duplicateAudioAsset).toHaveBeenCalledTimes(2);
    state.dismiss();
    expect(onSettled).toHaveBeenCalledWith({
      confirmed: [accepted('21').data],
      uncertain: 0,
      blocked: 1,
      pending: 1,
    });
  });

  it('does not silently rekey or replace a definitive validation refusal', async () => {
    API.duplicateAudioAsset.mockRejectedValueOnce({
      response: { status: 422 },
    });
    const { state, review } = fixture();
    await state.open();
    state.items.value[0].name = 'SYNTHETIC preserved name';
    review();
    await state.save();
    expect(state.items.value[0].name).toBe('SYNTHETIC preserved name');
    expect(state.items.value[0].status).toBe('blocked');
    expect(state.items.value[1].payload).toBeNull();
    review();
    await state.save();
    expect(API.duplicateAudioAsset).toHaveBeenCalledOnce();
  });

  it('does not send another source or disclose late receipts after a profile change during the first copy', async () => {
    const gate = deferred();
    API.duplicateAudioAsset.mockImplementationOnce(() => gate.promise);
    const { state, review, contextKey, onSettled } = fixture();
    await state.open();
    review();
    const saving = state.save();
    await flushPromises();
    contextKey.value = 'SYNTHETIC different profile';
    gate.resolve(accepted('21'));
    await saving;
    expect(state.items.value).toEqual([]);
    expect(state.active.value).toBe(false);
    expect(API.duplicateAudioAsset).toHaveBeenCalledOnce();
    expect(onSettled).not.toHaveBeenCalled();
  });

  it('clears private partial results after native permission withdrawal instead of reporting them in another profile', async () => {
    API.duplicateAudioAsset
      .mockResolvedValueOnce(accepted('21'))
      .mockRejectedValueOnce({ response: { status: 401 } });
    const { state, review, onDenied, onSettled } = fixture();
    await state.open();
    review();
    await state.save();
    expect(state.items.value).toEqual([]);
    expect(onDenied).toHaveBeenCalledOnce();
    state.dismiss();
    expect(onSettled).not.toHaveBeenCalled();
  });

  it.each(['account', 'unit', 'revision', 'inspection', 'readiness'])(
    'does not copy a source with changed native %s at review',
    async changed => {
      const data = { account_id: '1', item: source('21') };
      if (changed === 'account') data.account_id = '2';
      if (changed === 'unit') data.item.unit_id = '11';
      if (changed === 'revision') data.item.revision = 'e'.repeat(64);
      if (changed === 'inspection')
        data.item.latest_version.technical_verification.id = '999';
      if (changed === 'readiness')
        data.item.latest_version.technical_verification.ready = false;
      API.audioAsset.mockResolvedValueOnce({ data });
      const { state, review } = fixture();
      await state.open();
      review();
      await state.save();
      expect(state.verified.value).toBe(false);
      expect(state.error.value).toBe('SOURCE_CHANGED');
      expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
    }
  );

  it('invalidates manual review after changing draft names and refuses an empty name', async () => {
    const { state, review } = fixture();
    await state.open();
    review();
    state.items.value[0].name = 'SYNTHETIC edited';
    expect(state.reviewed.value).toBe(false);
    state.items.value[0].name = '  ';
    review();
    expect(state.canSave.value).toBe(false);
    await state.save();
    expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
  });

  it('does not silently submit an old frozen name or destination after an uncertain response and changed draft', async () => {
    API.duplicateAudioAsset.mockRejectedValueOnce(
      new Error('SYNTHETIC lost response')
    );
    const { state, review } = fixture();
    await state.open();
    review();
    await state.save();
    state.items.value[0].name = 'SYNTHETIC conflicting new name';
    review();
    expect(state.canSave.value).toBe(false);
    await state.save();
    expect(API.duplicateAudioAsset).toHaveBeenCalledOnce();
  });

  it.each([
    'account',
    'unit',
    'source_id',
    'source_version_id',
    'hash',
    'number',
    'unsafe_id',
  ])(
    'preserves an uncertain operation rather than accepting a mismatched %s receipt',
    async changed => {
      const result = accepted('21');
      if (changed === 'account') result.data.account_id = '2';
      if (changed === 'unit') result.data.item.unit_id = '11';
      if (changed === 'source_id') result.data.item.id = '21';
      if (changed === 'source_version_id')
        result.data.received_version.id = '121';
      if (changed === 'hash')
        result.data.received_version.sha256 = 'e'.repeat(64);
      if (changed === 'number') result.data.received_version.number = 2;
      if (changed === 'unsafe_id')
        result.data.item.id = Number('9007199254740993');
      API.duplicateAudioAsset.mockResolvedValueOnce(result);
      const { state, review } = fixture();
      await state.open();
      review();
      await state.save();
      expect(state.confirmed.value).toHaveLength(0);
      expect(state.uncertain.value).toHaveLength(1);
      expect(state.items.value[1].payload).toBeNull();
      expect(API.duplicateAudioAsset).toHaveBeenCalledOnce();
    }
  );

  it('rejects duplicate source selection without creating redundant copy requests', async () => {
    const { state, review } = fixture([selected(), selected()]);
    await state.open();
    review();
    await state.save();
    expect(state.verified.value).toBe(false);
    expect(API.duplicateAudioAsset).not.toHaveBeenCalled();
  });

  it('does not accept one copied identity as the receipt for two different sources', async () => {
    API.duplicateAudioAsset
      .mockResolvedValueOnce(accepted('21'))
      .mockResolvedValueOnce(accepted('21'));
    const { state, review } = fixture();
    await state.open();
    review();
    await state.save();
    expect(state.confirmed.value).toHaveLength(1);
    expect(state.uncertain.value).toHaveLength(1);
    expect(state.complete.value).toBe(false);
  });

  it('ignores a late source review response after a unit change', async () => {
    const gate = deferred();
    API.audioAsset.mockImplementationOnce(() => gate.promise);
    const { state, unitId } = fixture();
    const opening = state.open();
    await flushPromises();
    unitId.value = '11';
    gate.resolve({ data: { account_id: '1', item: source('21') } });
    await opening;
    expect(state.items.value).toEqual([]);
    expect(state.verified.value).toBe(false);
    expect(API.audioAsset).toHaveBeenCalledOnce();
  });
});
