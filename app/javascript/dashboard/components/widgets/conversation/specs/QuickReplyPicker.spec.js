import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import Picker from '../QuickReplyPicker.vue';
import API from 'dashboard/api/cannedResponse';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/api/cannedResponse', () => ({
  default: { get: vi.fn(), preview: vi.fn(), file: vi.fn(), deliver: vi.fn() },
}));
enableAutoUnmount(afterEach);
const mountPicker = (values = {}) =>
  mount(Picker, {
    props: {
      accountId: 1,
      conversationId: 11,
      canAttach: () => true,
      isContextCurrent: () => true,
      onInsert: vi.fn().mockResolvedValue(),
      ...values,
    },
    global: {
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    },
  });
const click = async (wrapper, label) =>
  wrapper
    .findAll('button')
    .find(button => button.text().includes(label))
    .trigger('click');
beforeEach(() => {
  vi.clearAllMocks();
  HTMLDialogElement.prototype.showModal = vi.fn();
  HTMLDialogElement.prototype.close = vi.fn();
  API.get.mockResolvedValue({
    data: [{ id: 3, short_code: 'Greeting', content: 'Hello [nome]' }],
  });
  API.preview.mockResolvedValue({
    data: {
      id: 3,
      content: 'Hello Synthetic',
      unresolved: [],
      revision: 'revision-1',
      actor_id: 5,
    },
  });
  API.deliver.mockResolvedValue({ data: { id: 99 } });
});
describe('native quick reply review', () => {
  it('loads the existing catalog and resolves only the selected conversation', async () => {
    const w = mountPicker();
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    expect(API.preview).toHaveBeenCalledWith(3, 11, 1);
    expect(w.get('textarea').element.value).toBe('Hello Synthetic');
    expect(API.deliver).not.toHaveBeenCalled();
  });
  it('inserts the reviewed text without sending', async () => {
    const insert = vi.fn().mockResolvedValue();
    const w = mountPicker({ onInsert: insert });
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    await w.get('textarea').setValue('Reviewed');
    await click(w, 'QUICK.INSERT');
    await flushPromises();
    expect(insert).toHaveBeenCalledWith({
      content: 'Reviewed',
      file: undefined,
      conversationId: 11,
      accountId: 1,
      authorityKey: '',
    });
    expect(API.deliver).not.toHaveBeenCalled();
  });
  it('discards a late preview after changing conversation or authority', async () => {
    let resolve;
    API.preview.mockImplementationOnce(
      () =>
        new Promise(done => {
          resolve = done;
        })
    );
    const w = mountPicker();
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await w.setProps({ conversationId: 12, authorityKey: 'other-role' });
    resolve({ data: { id: 3, content: 'Secret from old conversation' } });
    await flushPromises();
    expect(w.text()).not.toContain('Secret from old conversation');
    expect(w.find('textarea').exists()).toBe(false);
  });
  it('requires the separate confirmation before native delivery and blocks a double click', async () => {
    let finish;
    API.deliver.mockImplementationOnce(
      () =>
        new Promise(done => {
          finish = done;
        })
    );
    const w = mountPicker();
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    await click(w, 'QUICK.SEND');
    expect(API.deliver).not.toHaveBeenCalled();
    const dialogs = w.findAllComponents({ name: 'Dialog' });
    dialogs[1].vm.$emit('confirm');
    dialogs[1].vm.$emit('confirm');
    await flushPromises();
    expect(API.deliver).toHaveBeenCalledTimes(1);
    expect(API.deliver.mock.calls[0][1]).toMatchObject({
      conversation_id: 11,
      confirmed: true,
      content: 'Hello Synthetic',
      revision: 'revision-1',
      actor_id: 5,
    });
    finish({ data: { id: 99, conversation_id: 11 } });
    await flushPromises();
    expect(w.emitted('delivered')).toEqual([[{ id: 99, conversation_id: 11 }]]);
  });
  it('preserves content and intent after an uncertain send failure', async () => {
    API.deliver.mockRejectedValue(new Error('Network lost'));
    const w = mountPicker();
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    const confirmation = w.findAllComponents({ name: 'Dialog' })[1];
    confirmation.vm.$emit('confirm');
    await flushPromises();
    const first = API.deliver.mock.calls[0][1];
    expect(w.get('textarea').element.value).toBe('Hello Synthetic');
    expect(w.get('[role="alert"]').text()).toContain('QUICK.SEND_ERROR');
    confirmation.vm.$emit('confirm');
    await flushPromises();
    expect(API.deliver.mock.calls[1][1].delivery_key).toBe(first.delivery_key);
  });
  it('keeps the preview when attachment download/upload fails', async () => {
    API.preview.mockResolvedValue({
      data: {
        id: 3,
        content: 'With file',
        file: {
          filename: 'test.pdf',
          content_type: 'application/pdf',
          byte_size: 10,
        },
      },
    });
    API.file.mockRejectedValue(new Error('Upload unavailable'));
    const w = mountPicker();
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    await click(w, 'QUICK.INSERT');
    await flushPromises();
    expect(w.get('textarea').element.value).toBe('With file');
    expect(w.text()).toContain('test.pdf');
    expect(w.get('[role="alert"]').text()).toContain('QUICK.ERROR');
  });
  it('disables delivery when the native channel cannot combine text and media', async () => {
    API.preview.mockResolvedValue({
      data: { id: 3, content: 'With image', file: { filename: 'test.png' } },
    });
    const w = mountPicker({ canSendCombined: false });
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    expect(
      w
        .findAll('button')
        .find(button => button.text().includes('QUICK.SEND'))
        .attributes('disabled')
    ).toBeDefined();
    expect(API.deliver).not.toHaveBeenCalled();
  });
  it('rejects a stale live store context even before the prop watcher runs', async () => {
    let current = true;
    const w = mountPicker({ isContextCurrent: () => current });
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    current = false;
    w.findAllComponents({ name: 'Dialog' })[1].vm.$emit('confirm');
    await flushPromises();
    expect(API.deliver).not.toHaveBeenCalled();
  });
  it('keeps unresolved variables reviewable and prevents direct delivery', async () => {
    API.preview.mockResolvedValue({
      data: { id: 3, content: 'Hello [nome]', actor_id: 5 },
    });
    const w = mountPicker();
    await w.vm.open();
    await flushPromises();
    await click(w, 'Greeting');
    await flushPromises();
    expect(
      w
        .findAll('button')
        .find(b => b.text().includes('QUICK.SEND'))
        .attributes('disabled')
    ).toBeDefined();
    await w.get('textarea').setValue('Hello corrected');
    expect(
      w
        .findAll('button')
        .find(b => b.text().includes('QUICK.SEND'))
        .attributes('disabled')
    ).toBeUndefined();
  });
  it('uses the same authorized preview for a model chosen with the existing slash shortcut', async () => {
    const w = mountPicker();
    await w.vm.open(3);
    await flushPromises();
    expect(API.preview).toHaveBeenCalledWith(3, 11, 1);
    expect(w.get('textarea').element.value).toBe('Hello Synthetic');
    expect(API.deliver).not.toHaveBeenCalled();
  });
});
