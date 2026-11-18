import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useRoutingDraftEditor } from './useRoutingDraftEditor';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: {
    configurationRecord: vi.fn(),
    ivrReference: vi.fn(),
    saveRoutingRule: vi.fn(),
  },
}));
const original = 'a'.repeat(64);
const record = fields => ({
  id: 9,
  version: 2,
  rule_key: 'SYNTHETIC rule',
  kind: 'ddd',
  source_value: '11',
  priority: 1,
  state: 'draft',
  target_unit_id: 3,
  target_queue_id: 4,
  revision: original,
  ...fields,
});
const render = () => {
  const accountId = ref('1');
  const allowed = ref(true);
  const dialog = ref({ open: vi.fn(), close: vi.fn() });
  const saved = vi.fn();
  let editor;
  mount(
    defineComponent({
      setup() {
        editor = useRoutingDraftEditor({
          accountId,
          allowed,
          dialog,
          t: key => key,
          saved,
        });
        return () => h('div');
      },
    })
  );
  return { editor, accountId, allowed, dialog, saved };
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.configurationRecord.mockResolvedValue({ data: { item: record() } });
  API.ivrReference.mockResolvedValue({ data: { item: { id: 4, unit_id: 3 } } });
  API.saveRoutingRule.mockResolvedValue({ data: { item: record() } });
});

describe('native routing draft editor', () => {
  it('creates a local draft through the existing API with no invented publication or legacy opaque fields', async () => {
    const { editor, saved } = render();
    await editor.open();
    Object.assign(editor.draft.value, {
      rule_key: 'SYNTHETIC created',
      target_unit_id: '3',
    });
    await editor.save();
    expect(API.saveRoutingRule).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({
        state: 'draft',
        rule_key: 'SYNTHETIC created',
        version: 1,
      }),
      undefined,
      {}
    );
    expect(saved).toHaveBeenCalledOnce();
  });

  it('edits the freshly retrieved native identity and canonical revision without overwriting advanced conditions', async () => {
    API.configurationRecord.mockResolvedValue({
      data: {
        item: record({
          conditions: { private: 'SYNTHETIC opaque' },
          starts_at: '2026-11-01',
        }),
      },
    });
    const { editor } = render();
    await editor.open(9);
    editor.draft.value.source_value = '21';
    await editor.save();
    const [account, payload, id, options] = API.saveRoutingRule.mock.calls[0];
    expect([account, id, options]).toEqual([
      '1',
      9,
      { expected_revision: original },
    ]);
    expect(payload.source_value).toBe('21');
    expect(payload).not.toHaveProperty('conditions');
    expect(payload).not.toHaveProperty('starts_at');
  });

  it('retains the local draft and blocks retry until the latest native revision is explicitly reviewed', async () => {
    const { editor } = render();
    await editor.open(9);
    editor.draft.value.source_value = '21';
    API.saveRoutingRule.mockRejectedValueOnce({
      response: {
        status: 409,
        data: { error: 'stale_configuration_revision' },
      },
    });
    await editor.save();
    expect(editor.draft.value.source_value).toBe('21');
    expect(editor.revision.canSave.value).toBe(false);
    await editor.save();
    expect(API.saveRoutingRule).toHaveBeenCalledTimes(1);
    API.configurationRecord.mockResolvedValue({
      data: { item: record({ revision: 'b'.repeat(64), source_value: '31' }) },
    });
    await editor.revision.reload();
    expect(editor.revision.state.latest.source_value).toBe('31');
    expect(editor.draft.value.source_value).toBe('21');
    editor.revision.review(true);
    await editor.save();
    expect(API.saveRoutingRule).toHaveBeenLastCalledWith(
      '1',
      expect.objectContaining({ source_value: '21' }),
      9,
      { expected_revision: 'b'.repeat(64) }
    );
  });

  it('does not mutate published historical records', async () => {
    API.configurationRecord.mockResolvedValue({
      data: { item: record({ state: 'published' }) },
    });
    const { editor } = render();
    await editor.open(9);
    await editor.save();
    expect(editor.editing.value.state).toBe('published');
    expect(API.saveRoutingRule).not.toHaveBeenCalled();
  });

  it('keeps a missing revision blocked rather than falling back to the legacy API', async () => {
    API.configurationRecord.mockResolvedValue({
      data: { item: record({ revision: null }) },
    });
    const { editor } = render();
    await editor.open(9);
    await editor.save();
    expect(editor.revision.canSave.value).toBe(false);
    expect(API.saveRoutingRule).not.toHaveBeenCalled();
  });

  it('resolves the native picker context for a legacy queue-only rule without changing its stored target', async () => {
    API.configurationRecord.mockResolvedValue({
      data: { item: record({ target_unit_id: null }) },
    });
    const { editor } = render();
    await editor.open(9);
    expect(API.ivrReference).toHaveBeenCalledWith('1', 'queues', 4);
    expect(editor.referenceUnit.value).toBe('3');
    expect(editor.draft.value.target_unit_id).toBeNull();
    await editor.save();
    expect(API.saveRoutingRule).toHaveBeenCalledWith(
      '1',
      expect.objectContaining({ target_unit_id: null, target_queue_id: 4 }),
      9,
      { expected_revision: original }
    );
  });

  it('discards a late private detail when the account changes', async () => {
    let finish;
    API.configurationRecord.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { editor, accountId, dialog } = render();
    const pending = editor.open(9);
    accountId.value = '2';
    await flushPromises();
    finish({ data: { item: record({ rule_key: 'PRIVATE OLD ACCOUNT' }) } });
    await pending;
    expect(editor.editing.value).toBeNull();
    expect(editor.draft.value).toEqual({});
    expect(dialog.value.open).not.toHaveBeenCalled();
  });

  it('clears and refuses further writes after configure authority is lost', async () => {
    const { editor, allowed } = render();
    await editor.open(9);
    allowed.value = false;
    await flushPromises();
    await editor.save();
    expect(editor.draft.value).toEqual({});
    expect(editor.visible.value).toBe(false);
    expect(API.saveRoutingRule).not.toHaveBeenCalled();
  });

  it('preserves data on a failed save and prevents a duplicate while its outcome is pending', async () => {
    const { editor } = render();
    await editor.open(9);
    editor.draft.value.source_value = '21';
    let fail;
    API.saveRoutingRule.mockImplementationOnce(
      () =>
        new Promise((_resolve, reject) => {
          fail = reject;
        })
    );
    const pending = editor.save();
    await editor.save();
    expect(API.saveRoutingRule).toHaveBeenCalledTimes(1);
    fail({ response: { status: 422 } });
    await pending;
    expect(editor.draft.value.source_value).toBe('21');
    expect(editor.visible.value).toBe(true);
    expect(editor.error.value).toBe(
      'JRC_CONTACT_CENTER.ROUTING_DRAFTS.SAVE_ERROR'
    );
    expect(editor.saving.value).toBe(false);
  });

  it('rejects a mismatched fetched record before opening or capturing its revision', async () => {
    API.configurationRecord.mockResolvedValue({
      data: { item: record({ id: 10 }) },
    });
    const { editor, dialog } = render();
    await editor.open(9);
    expect(dialog.value.open).not.toHaveBeenCalled();
    expect(editor.editing.value).toBeNull();
    expect(editor.error.value).toBe('JRC_CONTACT_CENTER.COMMON.ERROR');
  });
});
