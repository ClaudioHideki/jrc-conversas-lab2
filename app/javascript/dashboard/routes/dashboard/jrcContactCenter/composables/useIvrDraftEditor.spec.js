import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useIvrDraftEditor } from './useIvrDraftEditor';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { configurationRecord: vi.fn(), saveIvrDraft: vi.fn() },
}));
const graph = () => ({
  schema_version: 1,
  start: 'end',
  nodes: [{ id: 'end', type: 'end' }],
});
const saved = (revision = 1) => ({
  id: '10',
  unit_id: '7',
  name: 'SYNTHETIC draft',
  status: 'draft',
  revision,
  definition: graph(),
});
const mountEditor = (initialId = null) => {
  const accountId = ref('1');
  let editor;
  const wrapper = mount(
    defineComponent({
      setup() {
        editor = useIvrDraftEditor({ accountId, initialId });
        return () => h('div');
      },
    })
  );
  return { wrapper, accountId, editor };
};
const prepare = editor => {
  editor.draft.value.name = 'SYNTHETIC draft';
  editor.setUnit('7');
  editor.setGraph(graph());
};
enableAutoUnmount(afterEach);
beforeEach(() => {
  vi.clearAllMocks();
  API.saveIvrDraft.mockResolvedValue({
    data: { item: saved(), replayed: false, latest_revision: 1 },
  });
  API.configurationRecord.mockResolvedValue({
    data: { item: saved(), timezone: 'UTC' },
  });
});

describe('local IVR editor persistence and safe retries', () => {
  it('sends the native precondition and a UUID, then reloads the actual accepted head', async () => {
    const { editor } = mountEditor();
    prepare(editor);
    expect(await editor.save()).toBe(true);
    expect(API.saveIvrDraft).toHaveBeenCalledOnce();
    const [account, id, body] = API.saveIvrDraft.mock.calls[0];
    expect([account, id]).toEqual(['1', null]);
    expect(body).toMatchObject({
      unit_id: '7',
      expected_revision: 0,
      definition: graph(),
      status: 'draft',
    });
    expect(body.request_id).toMatch(/^[0-9a-f-]{36}$/);
    expect(API.configurationRecord).toHaveBeenCalledWith(
      '1',
      'ivr_drafts',
      '10'
    );
    expect(editor.dirty.value).toBe(false);
    expect(editor.state.saved).toBe(true);
  });

  it('blocks double submission while a save is in flight', async () => {
    let finish;
    API.saveIvrDraft.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { editor } = mountEditor();
    prepare(editor);
    const pending = editor.save();
    expect(editor.locked.value).toBe(true);
    expect(await editor.save()).toBe(false);
    finish({ data: { item: saved() } });
    expect(await pending).toBe(true);
    expect(API.saveIvrDraft).toHaveBeenCalledOnce();
  });

  it('preserves the exact body and UUID after an uncertain network failure and locks edits until a safe retry', async () => {
    API.saveIvrDraft.mockRejectedValueOnce(new Error('network interruption'));
    const { editor } = mountEditor();
    prepare(editor);
    expect(await editor.save()).toBe(false);
    const first = API.saveIvrDraft.mock.calls[0];
    expect(editor.state.uncertain).toBe(true);
    expect(editor.locked.value).toBe(true);
    expect(editor.canSave.value).toBe(false);
    expect(await editor.save()).toBe(false);
    expect(await editor.save('draft', true)).toBe(true);
    expect(API.saveIvrDraft.mock.calls[1]).toEqual(first);
    expect(editor.state.uncertain).toBe(false);
  });

  it('retries the original create operation when acceptance succeeded but the follow-up GET failed', async () => {
    API.configurationRecord.mockRejectedValueOnce(
      new Error('lost follow-up read')
    );
    const { editor } = mountEditor();
    prepare(editor);
    expect(await editor.save()).toBe(false);
    expect(editor.recordId.value).toBe('10');
    expect(editor.state.loaded).toBe(false);
    expect(editor.state.uncertain).toBe(true);
    expect(await editor.save('draft', true)).toBe(true);
    expect(API.saveIvrDraft.mock.calls[1]).toEqual(
      API.saveIvrDraft.mock.calls[0]
    );
    expect(API.saveIvrDraft.mock.calls[1][1]).toBeNull();
  });

  it('preserves editable content after a known validation rejection and uses a new UUID for changed data', async () => {
    API.saveIvrDraft.mockRejectedValueOnce({
      response: { status: 422, data: { error: 'invalid_ivr_graph' } },
    });
    const { editor } = mountEditor();
    prepare(editor);
    expect(await editor.save()).toBe(false);
    expect(editor.state.uncertain).toBe(false);
    expect(editor.locked.value).toBe(false);
    expect(editor.draft.value.definition).toEqual(graph());
    editor.draft.value.name = 'SYNTHETIC revised';
    await editor.save();
    expect(API.saveIvrDraft.mock.calls[1][2].request_id).not.toBe(
      API.saveIvrDraft.mock.calls[0][2].request_id
    );
  });

  it('does not retry an authorization rejection or discard the operator draft', async () => {
    API.saveIvrDraft.mockRejectedValueOnce({ response: { status: 401 } });
    const { editor } = mountEditor();
    prepare(editor);
    expect(await editor.save()).toBe(false);
    expect(editor.state.denied).toBe(true);
    expect(editor.draft.value.name).toBe('SYNTHETIC draft');
    expect(await editor.save()).toBe(false);
    expect(API.saveIvrDraft).toHaveBeenCalledOnce();
  });

  it('does not save blank defaults after the initial authorized read fails', async () => {
    API.configurationRecord.mockRejectedValueOnce({
      response: { status: 404 },
    });
    const { editor } = mountEditor('10');
    await editor.load();
    expect(editor.state.loaded).toBe(false);
    expect(editor.locked.value).toBe(true);
    expect(await editor.save()).toBe(false);
    expect(API.saveIvrDraft).not.toHaveBeenCalled();
  });

  it('keeps a stale draft while requiring an explicit current-state review before another revision', async () => {
    const { editor } = mountEditor('10');
    await editor.load();
    editor.draft.value.name = 'SYNTHETIC retained draft';
    API.saveIvrDraft.mockRejectedValueOnce({
      response: { status: 409, data: { error: 'stale_ivr_revision' } },
    });
    expect(await editor.save()).toBe(false);
    expect(editor.canSave.value).toBe(false);
    API.configurationRecord.mockResolvedValueOnce({
      data: { item: saved(2), timezone: 'UTC' },
    });
    await editor.revision.reload();
    expect(editor.draft.value.name).toBe('SYNTHETIC retained draft');
    expect(editor.canSave.value).toBe(false);
    editor.revision.review(true);
    await editor.save();
    expect(API.saveIvrDraft.mock.calls[1][2].expected_revision).toBe(2);
  });

  it('never accepts unapplied or malformed JSON as the currently edited graph', () => {
    const { editor } = mountEditor();
    prepare(editor);
    editor.jsonText.value = '{';
    editor.jsonPending.value = true;
    expect(editor.canSave.value).toBe(false);
    expect(() => editor.applyJson(editor.jsonText.value)).toThrow();
    expect(editor.draft.value.definition).toEqual(graph());
    editor.discardJson();
    expect(editor.jsonPending.value).toBe(false);
    expect(JSON.parse(editor.jsonText.value)).toEqual(graph());
  });

  it('ignores a late save after the editor context was unmounted', async () => {
    let finish;
    API.saveIvrDraft.mockImplementationOnce(
      () =>
        new Promise(resolve => {
          finish = resolve;
        })
    );
    const { editor, wrapper } = mountEditor();
    prepare(editor);
    const pending = editor.save();
    wrapper.unmount();
    finish({ data: { item: saved() } });
    expect(await pending).toBe(false);
    await flushPromises();
    expect(API.configurationRecord).not.toHaveBeenCalled();
  });
});
