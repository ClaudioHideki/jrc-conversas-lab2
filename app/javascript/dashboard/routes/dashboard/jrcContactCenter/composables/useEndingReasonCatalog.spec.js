import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import {
  useEndingReasonCatalog,
  validEndingReason,
} from './useEndingReasonCatalog';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { acwPolicy: vi.fn(), updateAcwPolicy: vi.fn() },
}));
enableAutoUnmount(afterEach);
afterEach(() => vi.clearAllMocks());
const row = () => ({
  code: 'synthetic',
  name: 'SYNTHETIC reason',
  category: 'SYNTHETIC',
  description: '',
  order: 0,
  active: true,
});
const response = (entries = [], options = {}) => ({
  data: {
    item: {
      id: '1',
      revision: 'a'.repeat(64),
      limits: { voice: 180, whatsapp: 180 },
      voice_reason_catalog: { version: entries.length ? 1 : 0, entries },
      ...options,
    },
  },
});
const fixture = () => {
  const accountId = ref('1');
  let catalog;
  const wrapper = mount(
    defineComponent({
      setup() {
        catalog = useEndingReasonCatalog({ accountId });
        return () => null;
      },
    })
  );
  return { accountId, catalog, wrapper };
};

describe('native ending reason configuration lifecycle', () => {
  it('loads the authorized account configuration and persists only the catalogue with its exact precondition', async () => {
    API.acwPolicy.mockResolvedValue(response());
    API.updateAcwPolicy.mockResolvedValue(
      response([row()], { revision: 'b'.repeat(64) })
    );
    const { catalog } = fixture();
    await flushPromises();
    catalog.entries.value = [row()];
    expect(catalog.canSave.value).toBe(true);
    await catalog.save();
    expect(API.updateAcwPolicy).toHaveBeenCalledWith(
      '1',
      { voice: 180, whatsapp: 180 },
      {
        expected_revision: 'a'.repeat(64),
        voice_reason_catalog: [row()],
      }
    );
    expect(catalog.dirty.value).toBe(false);
    expect(catalog.saved.value).toBe(true);
    expect(catalog.version.value).toBe(1);
  });

  it('keeps drafts after a conflict and never overwrites newer channel limits during explicit review', async () => {
    API.acwPolicy.mockResolvedValueOnce(response()).mockResolvedValueOnce(
      response([], {
        revision: 'c'.repeat(64),
        limits: { voice: 300, whatsapp: 240 },
      })
    );
    API.updateAcwPolicy
      .mockRejectedValueOnce({
        response: {
          status: 409,
          data: { error: 'stale_configuration_revision' },
        },
      })
      .mockResolvedValueOnce(response([row()]));
    const { catalog } = fixture();
    await flushPromises();
    catalog.entries.value = [row()];
    await catalog.save();
    expect(catalog.entries.value).toEqual([row()]);
    expect(catalog.canSave.value).toBe(false);
    await catalog.revision.reload();
    expect(catalog.canSave.value).toBe(false);
    catalog.revision.review(true);
    await catalog.save();
    expect(API.updateAcwPolicy).toHaveBeenLastCalledWith(
      '1',
      { voice: 300, whatsapp: 240 },
      {
        expected_revision: 'c'.repeat(64),
        voice_reason_catalog: [row()],
      }
    );
  });

  it('preserves a draft after an uncertain response and blocks a blind retry until the native state is reviewed', async () => {
    API.acwPolicy.mockResolvedValue(response());
    API.updateAcwPolicy.mockRejectedValue(
      new Error('SYNTHETIC connection lost')
    );
    const { catalog } = fixture();
    await flushPromises();
    catalog.entries.value = [row()];
    await catalog.save();
    expect(catalog.error.value).toBe('SAVE_FAILED');
    expect(catalog.entries.value).toEqual([row()]);
    expect(catalog.revision.state.conflict).toBe(true);
    await catalog.save();
    expect(API.updateAcwPolicy).toHaveBeenCalledTimes(1);
  });

  it('prevents a second write while the first is pending', async () => {
    let finish;
    API.acwPolicy.mockResolvedValue(response());
    API.updateAcwPolicy.mockImplementation(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { catalog } = fixture();
    await flushPromises();
    catalog.entries.value = [row()];
    const writing = catalog.save();
    await catalog.save();
    expect(API.updateAcwPolicy).toHaveBeenCalledTimes(1);
    finish(response([row()]));
    await writing;
    expect(catalog.saved.value).toBe(true);
  });

  it('rejects invalid rows and duplicate codes before making a write', async () => {
    API.acwPolicy.mockResolvedValue(response());
    const { catalog } = fixture();
    await flushPromises();
    catalog.entries.value = [{ ...row(), active: 'true' }];
    await catalog.save();
    catalog.entries.value = [row(), row()];
    await catalog.save();
    expect(catalog.valid.value).toBe(false);
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
  });

  it('clears protected data when current configure access is denied', async () => {
    API.acwPolicy.mockResolvedValue(response([row()]));
    API.updateAcwPolicy.mockRejectedValue({ response: { status: 401 } });
    const { catalog } = fixture();
    await flushPromises();
    catalog.entries.value[0].name = 'SYNTHETIC change';
    await catalog.save();
    expect(catalog.error.value).toBe('DENIED');
    expect(catalog.entries.value).toEqual([]);
    expect(catalog.baseline.value).toEqual([]);
    expect(catalog.canSave.value).toBeFalsy();
  });

  it('discards an old account response after a rapid account change', async () => {
    let finish;
    API.acwPolicy
      .mockImplementationOnce(
        () =>
          new Promise(resolve => {
            finish = resolve;
          })
      )
      .mockResolvedValueOnce(response([], { id: '2' }));
    const { catalog, accountId } = fixture();
    accountId.value = '2';
    await flushPromises();
    finish(response([row()]));
    await flushPromises();
    expect(catalog.entries.value).toEqual([]);
    expect(catalog.error.value).toBe('');
    expect(catalog.revision.state.account).toBe('2');
  });

  it('does not retain a mismatched account response or start automatic retries', async () => {
    API.acwPolicy.mockResolvedValue(response([row()], { id: '2' }));
    const { catalog } = fixture();
    await flushPromises();
    expect(catalog.entries.value).toEqual([]);
    expect(catalog.error.value).toBe('LOAD_FAILED');
    expect(API.acwPolicy).toHaveBeenCalledTimes(1);
  });

  it('leaves the last server baseline intact instead of refreshing over unsaved changes', async () => {
    API.acwPolicy.mockResolvedValue(response([row()]));
    const { catalog } = fixture();
    await flushPromises();
    catalog.entries.value[0].name = 'SYNTHETIC draft';
    await catalog.load();
    expect(API.acwPolicy).toHaveBeenCalledTimes(1);
    expect(catalog.baseline.value[0].name).toBe(row().name);
  });

  it('rejects fractional order, blank identifiers and over-limit descriptions without discarding legitimate false or zero', () => {
    expect(validEndingReason({ ...row(), active: false, order: 0 })).toBe(true);
    expect(validEndingReason({ ...row(), order: 0.5 })).toBe(false);
    expect(validEndingReason({ ...row(), code: ' leading' })).toBe(false);
    expect(validEndingReason({ ...row(), description: 'x'.repeat(2001) })).toBe(
      false
    );
  });
});

describe('explicit required ending reason queues', () => {
  it('uses only authorized selected queue labels and never includes display metadata in a policy write', async () => {
    API.acwPolicy.mockResolvedValue(
      response([row()], {
        voice_reason_catalog: {
          version: 2,
          entries: [row()],
          required_queue_ids: ['21'],
        },
        voice_reason_queues: [
          { id: '21', name: 'SYNTHETIC selected' },
          { id: '99', name: 'SYNTHETIC unrelated' },
        ],
      })
    );
    API.updateAcwPolicy.mockResolvedValue(
      response([row()], {
        voice_reason_catalog: {
          version: 3,
          entries: [row()],
          required_queue_ids: ['21'],
        },
        voice_reason_queues: [{ id: '21', name: 'SYNTHETIC current' }],
      })
    );
    const { catalog } = fixture();
    await flushPromises();
    expect(catalog.requiredQueues.value).toEqual([
      { id: '21', name: 'SYNTHETIC selected' },
    ]);
    catalog.entries.value[0].name = 'SYNTHETIC revised';
    await catalog.save();
    expect(API.updateAcwPolicy.mock.calls[0][2]).not.toHaveProperty(
      'voice_reason_queues'
    );
    expect(catalog.requiredQueues.value).toEqual([
      { id: '21', name: 'SYNTHETIC current' },
    ]);
  });

  it('clears queue labels immediately across accounts and on denied configuration writes', async () => {
    const item = response([row()], {
      voice_reason_catalog: {
        version: 2,
        entries: [row()],
        required_queue_ids: ['21'],
      },
      voice_reason_queues: [{ id: '21', name: 'SYNTHETIC private previous' }],
    });
    API.acwPolicy.mockResolvedValue(item);
    const { catalog, accountId } = fixture();
    await flushPromises();
    catalog.entries.value[0].name = 'SYNTHETIC draft';
    API.updateAcwPolicy.mockRejectedValueOnce({ response: { status: 401 } });
    await catalog.save();
    expect(catalog.requiredQueues.value).toEqual([]);
    await catalog.load();
    expect(catalog.requiredQueues.value).toHaveLength(1);
    let resolveNext;
    API.acwPolicy.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          resolveNext = resolve;
        })
    );
    accountId.value = '2';
    await flushPromises();
    expect(catalog.requiredQueues.value).toEqual([]);
    resolveNext(response([], { id: '2' }));
    await flushPromises();
    expect(catalog.requiredQueues.value).toEqual([]);
  });

  it('requires confirmation before saving newly selected queues through the existing native policy API', async () => {
    API.acwPolicy.mockResolvedValue(response([row()]));
    API.updateAcwPolicy.mockResolvedValue(
      response([row()], {
        voice_reason_catalog: {
          version: 2,
          entries: [row()],
          required_queue_ids: ['21'],
        },
      })
    );
    const { catalog } = fixture();
    await flushPromises();
    catalog.requiredQueueIds.value = ['21'];
    await flushPromises();
    expect(catalog.dirty.value).toBe(true);
    expect(catalog.canSave.value).toBe(false);
    await catalog.save();
    expect(API.updateAcwPolicy).not.toHaveBeenCalled();
    catalog.queueConfirmation.value = true;
    expect(catalog.canSave.value).toBe(true);
    await catalog.save();
    expect(API.updateAcwPolicy.mock.calls[0][2]).toMatchObject({
      voice_reason_required_queue_ids: ['21'],
      voice_reason_confirmation: true,
    });
    expect(catalog.requiredQueueIds.value).toEqual(['21']);
    expect(catalog.dirty.value).toBe(false);
  });

  it('invalidates confirmation after queue changes and blocks the last active reason from being removed', async () => {
    API.acwPolicy.mockResolvedValue(response([row()]));
    const { catalog } = fixture();
    await flushPromises();
    catalog.requiredQueueIds.value = ['21'];
    await flushPromises();
    catalog.queueConfirmation.value = true;
    catalog.requiredQueueIds.value = ['21', '22'];
    await flushPromises();
    expect(catalog.queueConfirmation.value).toBe(false);
    catalog.queueConfirmation.value = true;
    catalog.entries.value[0].active = false;
    expect(catalog.valid.value).toBe(false);
    expect(catalog.canSave.value).toBe(false);
  });

  it('keeps previously selected queue ids even when their native catalogue page is not currently displayed', async () => {
    API.acwPolicy.mockResolvedValue(
      response([row()], {
        voice_reason_catalog: {
          version: 3,
          entries: [row()],
          required_queue_ids: ['21', '950'],
        },
      })
    );
    const { catalog, accountId } = fixture();
    await flushPromises();
    catalog.entries.value[0].name = 'SYNTHETIC next';
    expect(catalog.requiredQueueIds.value).toEqual(['21', '950']);
    expect(catalog.canSave.value).toBe(true);
    accountId.value = '2';
    await flushPromises();
    expect(catalog.requiredQueueIds.value).toEqual([]);
    expect(catalog.error.value).toBe('LOAD_FAILED');
  });
});
