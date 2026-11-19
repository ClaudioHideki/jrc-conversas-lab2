import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { defineComponent, h, ref } from 'vue';
import { enableAutoUnmount, flushPromises, mount } from '@vue/test-utils';
import API from 'dashboard/api/jrcContactCenter';
import { useAcwFormEditor } from './useAcwFormEditor';

vi.mock('dashboard/api/jrcContactCenter', () => ({
  default: { configurationRecord: vi.fn(), saveAcwForm: vi.fn() },
}));
enableAutoUnmount(afterEach);
const item = (revision = 1, name = 'SYNTHETIC original') => ({
  id: '19',
  revision,
  name,
  description: '',
  status: 'active',
  definition: {
    fields: [
      {
        key: 'detail',
        label: 'SYNTHETIC question',
        type: 'text',
        required: true,
      },
    ],
  },
});
const mounted = () => {
  const accountId = ref('1');
  let editor;
  const wrapper = mount(
    defineComponent({
      setup() {
        editor = useAcwFormEditor({ accountId });
        return () => h('div');
      },
    })
  );
  return { editor, accountId, wrapper };
};
beforeEach(() => {
  vi.clearAllMocks();
  API.configurationRecord.mockResolvedValue({ data: { item: item() } });
  API.saveAcwForm.mockResolvedValue({
    data: { item: item(2), replayed: false },
  });
});

describe('ACW form library revision lifecycle', () => {
  it('loads the authorized account and form with the exact immutable revision', async () => {
    const { editor } = mounted();
    await editor.open('19');
    expect(API.configurationRecord).toHaveBeenCalledWith(
      '1',
      'acw_forms',
      '19'
    );
    expect(editor.revision.options()).toEqual({ expected_revision: 1 });
    expect(editor.dirty.value).toBe(false);
    expect(editor.canSave.value).toBe(true);
  });

  it('does not save a new empty schema or invent a required question', async () => {
    const { editor } = mounted();
    await editor.open(null);
    editor.draft.value.name = 'SYNTHETIC new';
    expect(editor.canSave.value).toBe(false);
    expect(await editor.save()).toBe(false);
    expect(API.saveAcwForm).not.toHaveBeenCalled();
    expect(editor.draft.value.definition.fields).toEqual([]);
  });

  it('saves the local draft with a UUID and an integer revision then reloads the committed server version', async () => {
    const { editor } = mounted();
    await editor.open('19');
    editor.draft.value.name = 'SYNTHETIC changed';
    API.configurationRecord.mockResolvedValueOnce({
      data: { item: item(2, 'SYNTHETIC changed') },
    });
    expect(await editor.save()).toBe(true);
    const [account, id, body] = API.saveAcwForm.mock.calls[0];
    expect([account, id]).toEqual(['1', '19']);
    expect(body).toMatchObject({
      name: 'SYNTHETIC changed',
      expected_revision: 1,
      status: 'active',
    });
    expect(body.request_id).toMatch(/^[a-f0-9-]{36}$/);
    expect(editor.draft.value.name).toBe('SYNTHETIC changed');
    expect(editor.revision.options()).toEqual({ expected_revision: 2 });
    expect(editor.dirty.value).toBe(false);
  });

  it('retains the exact local draft on a stale revision and requires explicit comparison before retrying', async () => {
    const { editor } = mounted();
    await editor.open('19');
    editor.draft.value.name = 'SYNTHETIC retained';
    API.saveAcwForm.mockRejectedValueOnce({
      response: { status: 409, data: { error: 'stale_acw_form_revision' } },
    });
    expect(await editor.save()).toBe(false);
    expect(editor.draft.value.name).toBe('SYNTHETIC retained');
    expect(editor.canSave.value).toBe(false);
    API.configurationRecord.mockResolvedValueOnce({
      data: { item: item(2, 'SYNTHETIC competitor') },
    });
    await editor.revision.reload();
    expect(editor.canSave.value).toBe(false);
    editor.revision.review(true);
    expect(editor.canSave.value).toBe(true);
    expect(editor.revision.options()).toEqual({ expected_revision: 2 });
    editor.draft.value.description = 'SYNTHETIC another change';
    expect(editor.canSave.value).toBe(false);
  });

  it('locks an uncertain request and explicitly retries the exact body, UUID and target without autosubmission', async () => {
    const { editor } = mounted();
    await editor.open('19');
    editor.draft.value.name = 'SYNTHETIC uncertain';
    API.saveAcwForm.mockRejectedValueOnce(new Error('synthetic lost response'));
    expect(await editor.save()).toBe(false);
    const original = structuredClone(API.saveAcwForm.mock.calls[0]);
    expect(editor.state.uncertain).toBe(true);
    expect(editor.locked.value).toBe(true);
    expect(await editor.save()).toBe(false);
    expect(API.saveAcwForm).toHaveBeenCalledTimes(1);
    API.configurationRecord.mockResolvedValueOnce({
      data: { item: item(2, 'SYNTHETIC uncertain') },
    });
    expect(await editor.save('active', true)).toBe(true);
    expect(API.saveAcwForm.mock.calls[1]).toEqual(original);
    expect(editor.state.uncertain).toBe(false);
  });

  it('also preserves the same receipt when the write succeeded but the subsequent reload failed', async () => {
    const { editor } = mounted();
    await editor.open('19');
    API.configurationRecord.mockRejectedValueOnce(
      new Error('synthetic reload loss')
    );
    expect(await editor.save()).toBe(false);
    const first = structuredClone(API.saveAcwForm.mock.calls[0]);
    expect(editor.state.uncertain).toBe(true);
    expect(await editor.save('active', true)).toBe(true);
    expect(API.saveAcwForm.mock.calls[1]).toEqual(first);
  });

  it.each([400, 422, 428])(
    'keeps a rejected draft editable after known validation status %s',
    async status => {
      const { editor } = mounted();
      await editor.open('19');
      editor.draft.value.name = 'SYNTHETIC rejected';
      API.saveAcwForm.mockRejectedValueOnce({ response: { status } });
      expect(await editor.save()).toBe(false);
      expect(editor.state.uncertain).toBe(false);
      expect(editor.draft.value.name).toBe('SYNTHETIC rejected');
      expect(editor.locked.value).toBe(false);
    }
  );

  it.each([401, 403, 404])(
    'blocks further edits and retries when native authority is denied with %s',
    async status => {
      const { editor } = mounted();
      await editor.open('19');
      API.saveAcwForm.mockRejectedValueOnce({ response: { status } });
      expect(await editor.save()).toBe(false);
      expect(editor.state.denied).toBe(true);
      expect(editor.locked.value).toBe(true);
      expect(await editor.save('active', true)).toBe(false);
      expect(API.saveAcwForm).toHaveBeenCalledTimes(1);
    }
  );

  it('does not archive a changed definition or create an already archived form', async () => {
    const { editor } = mounted();
    await editor.open('19');
    editor.draft.value.description = 'SYNTHETIC pending';
    expect(await editor.save('archived')).toBe(false);
    expect(API.saveAcwForm).not.toHaveBeenCalled();
  });

  it('serializes double clicks so only one actual write is submitted', async () => {
    const { editor } = mounted();
    await editor.open('19');
    let resolve;
    API.saveAcwForm.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const first = editor.save();
    expect(await editor.save()).toBe(false);
    resolve({ data: { item: item(2) } });
    await first;
    expect(API.saveAcwForm).toHaveBeenCalledTimes(1);
  });

  it('clears the former account draft and ignores a late response after switching account', async () => {
    const { editor, accountId } = mounted();
    let resolve;
    API.configurationRecord.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const loading = editor.open('19');
    accountId.value = '2';
    await flushPromises();
    resolve({ data: { item: item() } });
    expect(await loading).toBe(false);
    expect(editor.draft.value).toBeNull();
    expect(editor.recordId.value).toBeNull();
  });

  it('ignores an in-flight write response after unmount without starting the follow-up read', async () => {
    const { editor, wrapper } = mounted();
    await editor.open('19');
    let resolve;
    API.saveAcwForm.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const saving = editor.save();
    wrapper.unmount();
    resolve({ data: { item: item(2) } });
    expect(await saving).toBe(false);
    expect(API.configurationRecord).toHaveBeenCalledTimes(1);
  });
});
