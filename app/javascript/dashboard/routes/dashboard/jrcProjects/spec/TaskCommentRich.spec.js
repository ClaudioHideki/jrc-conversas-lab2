import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import Rich from '../components/TaskCommentRich.vue';
import { commentDraft, commentDraftKey } from '../commentDrafts';
import { request } from '../../jrcOperations/api';

vi.mock('../useProjects', () => ({
  useProjects: () => ({
    accountId: ref(1),
    projectText: (_key, fallback) => fallback,
  }),
}));
vi.mock('../commentDrafts', async original => ({
  ...(await original()),
  commentDraft: vi.fn(),
}));
vi.mock('../../jrcOperations/api', async original => ({
  ...(await original()),
  request: vi.fn(),
}));
const scope = { accountId: 1, userId: 2, projectId: 3, taskId: 4 };
let wrapper;
let drafts;
beforeEach(() => {
  drafts = new Map();
  commentDraft.mockImplementation(async (action, identity, value) => {
    const key = commentDraftKey(identity);
    if (action === 'get') return drafts.get(key);
    if (action === 'delete') return drafts.delete(key);
    drafts.set(key, value);
    return undefined;
  });
  URL.createObjectURL = vi.fn(() => 'blob:synthetic-image');
  URL.revokeObjectURL = vi.fn();
  request
    .mockReset()
    .mockResolvedValue(new Blob(['synthetic'], { type: 'image/png' }));
  Range.prototype.getClientRects = () => [];
  Range.prototype.getBoundingClientRect = () => ({
    left: 0,
    top: 0,
    right: 0,
    bottom: 0,
  });
});
afterEach(() => {
  wrapper?.unmount();
  vi.useRealTimers();
  vi.clearAllMocks();
});
const render = async props => {
  wrapper = mount(Rich, {
    attachTo: document.body,
    props: { scope, ...props },
    global: { stubs: { teleport: true } },
  });
  await flushPromises();
  return wrapper;
};
const submit = () =>
  wrapper
    .findAll('button')
    .find(button => button.text() === 'Registrar comentário');

describe('real ProseMirror task comment composer', () => {
  it('allows a replacement after removing staged images and retains removed files for undo', async () => {
    await render();
    const startedAt = Date.now();
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(startedAt + 1000);
    wrapper.vm.insertImages(
      Array.from(
        { length: 10 },
        (_, index) =>
          new File([`print ${index}`], `print-${index}.png`, {
            type: 'image/png',
          })
      )
    );
    await flushPromises();
    const editor = wrapper.get('.ProseMirror[contenteditable="true"]');
    vi.setSystemTime(startedAt + 2000);
    await editor.trigger('keydown', { key: 'Backspace', code: 'Backspace' });
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(9);
    vi.setSystemTime(startedAt + 3000);
    wrapper.vm.insertImages([
      new File(['replacement'], 'replacement.png', { type: 'image/png' }),
    ]);
    await flushPromises();
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(10);
    await submit().trigger('click');
    const names = wrapper
      .emitted('submit')[0][0]
      .images.map(image => image.file.name);
    expect(names).toHaveLength(10);
    expect(names).toContain('replacement.png');
    expect(names).not.toContain('print-9.png');
    // Each undo must consume the history produced by the preceding command.
    /* eslint-disable no-await-in-loop */
    for (
      let attempt = 0;
      attempt < 4 && !wrapper.find('img[alt="print-9.png"]').exists();
      attempt += 1
    ) {
      await wrapper.get('[title="Undo last change"]').trigger('mousedown');
      await flushPromises();
    }
    /* eslint-enable no-await-in-loop */
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(10);
    await submit().trigger('click');
    expect(
      wrapper.emitted('submit')[1][0].images.map(image => image.file.name)
    ).toContain('print-9.png');
    expect(URL.revokeObjectURL).not.toHaveBeenCalled();
    wrapper.unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalled();
  });

  it('counts persisted images toward the ten images in the current document', async () => {
    const images = Array.from({ length: 10 }, (_, index) => ({
      id: index + 10,
      key: `synthetic-image-${String(index).padStart(8, '0')}`,
    }));
    await render({
      comment: {
        id: 8,
        body: images
          .map(image => `![Print](comment-image:${image.key})`)
          .join('\n\n'),
        inline_images: images,
      },
    });
    wrapper.vm.insertImages([
      new File(['extra'], 'extra.png', { type: 'image/png' }),
    ]);
    await flushPromises();
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(10);
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
  });

  it('inserts multiple binary prints at the cursor and submits them with a trailing editable paragraph', async () => {
    await render();
    const files = [
      new File(['first'], 'first.png', { type: 'image/png' }),
      new File(['second'], 'second.png', { type: 'image/png' }),
    ];
    wrapper.vm.insertImages(files);
    await flushPromises();
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(2);
    expect(wrapper.findAll('.ProseMirror p').at(-1).find('img').exists()).toBe(
      false
    );
    await submit().trigger('click');
    const payload = wrapper.emitted('submit')[0][0];
    expect(payload.images.map(image => image.file.name)).toEqual([
      'first.png',
      'second.png',
    ]);
    expect(payload.body.indexOf('first.png')).toBeLessThan(
      payload.body.indexOf('second.png')
    );
    expect(payload.body).not.toContain('base64');
  });

  it('accepts the actual paste event used by clipboard prints', async () => {
    await render();
    const event = new Event('paste', { bubbles: true, cancelable: true });
    Object.defineProperty(event, 'clipboardData', {
      value: {
        files: [new File(['print'], 'print.png', { type: 'image/png' })],
        getData: () => '',
        types: ['Files'],
      },
    });
    wrapper.get('.ProseMirror').element.dispatchEvent(event);
    await flushPromises();
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(1);
    await submit().trigger('click');
    expect(wrapper.emitted('submit')[0][0].images).toHaveLength(1);
  });

  it('accepts files from the native file picker without navigating or submitting the surrounding page', async () => {
    await render();
    const picker = wrapper.get('input[type="file"]');
    Object.defineProperty(picker.element, 'files', {
      value: [new File(['selected'], 'selected.png', { type: 'image/png' })],
    });
    await picker.trigger('change');
    await flushPromises();
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(1);
    await submit().trigger('click');
    expect(wrapper.emitted('submit')[0][0].images[0].file.name).toBe(
      'selected.png'
    );
  });

  it('accepts a dropped image using the same binary attachment flow', async () => {
    await render();
    document.elementFromPoint = () => wrapper.get('.ProseMirror').element;
    const event = new Event('drop', { bubbles: true, cancelable: true });
    Object.defineProperties(event, {
      dataTransfer: {
        value: {
          files: [new File(['dropped'], 'dropped.png', { type: 'image/png' })],
          getData: () => '',
          types: ['Files'],
        },
      },
      clientX: { value: 0 },
      clientY: { value: 0 },
    });
    wrapper.get('.ProseMirror').element.dispatchEvent(event);
    await flushPromises();
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(1);
    await submit().trigger('click');
    expect(wrapper.emitted('submit')[0][0].images[0].file.name).toBe(
      'dropped.png'
    );
  });

  it('restores text and image blobs from the exact scoped draft and clears it only after acknowledgement', async () => {
    const file = new File(['print'], 'restore.png', { type: 'image/png' });
    drafts.set(commentDraftKey(scope), {
      body: 'Before\n\n![Print](comment-image:synthetic-image-00000001)\n\nAfter',
      requestKey: 'synthetic-comment-000001',
      images: [['synthetic-image-00000001', file]],
    });
    await render();
    expect(wrapper.text()).toContain('Before');
    expect(wrapper.text()).toContain('After');
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(1);
    await submit().trigger('click');
    const payload = wrapper.emitted('submit')[0][0];
    expect(payload.requestKey).toBe('synthetic-comment-000001');
    expect(drafts.has(commentDraftKey(scope))).toBe(true);
    await payload.onSaved();
    expect(drafts.has(commentDraftKey(scope))).toBe(false);
    expect(wrapper.findAll('.ProseMirror img')).toHaveLength(0);
  });

  it('does not restore another user or task draft', async () => {
    drafts.set(commentDraftKey({ ...scope, userId: 99 }), {
      body: 'Other user',
      images: [],
    });
    await render();
    expect(wrapper.text()).not.toContain('Other user');
    expect(submit().attributes('disabled')).toBeDefined();
  });

  it('fetches saved images through the scoped authenticated API and revokes object URLs on unmount', async () => {
    await render({
      readonly: true,
      comment: {
        id: 8,
        body: '![Print](comment-image:synthetic-image-00000001)',
        inline_images: [{ id: 9, key: 'synthetic-image-00000001' }],
      },
    });
    expect(request).toHaveBeenCalledWith(
      1,
      'projects/projects/3/tasks/4/comments/8/images/9',
      expect.objectContaining({
        responseType: 'blob',
        signal: expect.any(AbortSignal),
      })
    );
    expect(wrapper.find('.ProseMirror img').attributes('src')).toBe(
      'blob:synthetic-image'
    );
    await wrapper.find('.ProseMirror img').trigger('click');
    expect(wrapper.find('[role="dialog"]').exists()).toBe(true);
    wrapper.unmount();
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:synthetic-image');
  });

  it('rejects unsupported files and blocks insertion or duplicate submission while saving', async () => {
    await render();
    wrapper.vm.insertImages([
      new File(['bad'], 'bad.svg', { type: 'image/svg+xml' }),
    ]);
    await flushPromises();
    expect(wrapper.find('[role="alert"]').exists()).toBe(true);
    expect(wrapper.findAll('.ProseMirror img')).toHaveLength(0);
    await wrapper.setProps({ disabled: true });
    wrapper.vm.insertImages([
      new File(['print'], 'blocked.png', { type: 'image/png' }),
    ]);
    expect(wrapper.findAll('.ProseMirror img')).toHaveLength(0);
    await submit().trigger('click');
    expect(wrapper.emitted('submit')).toBeUndefined();
  });

  it('keeps the composer usable when local draft storage is unavailable', async () => {
    commentDraft.mockRejectedValue(
      new Error('Synthetic local storage unavailable')
    );
    await render();
    wrapper.vm.insertImages([
      new File(['print'], 'available.png', { type: 'image/png' }),
    ]);
    await flushPromises();
    expect(wrapper.text()).toContain('Synthetic local storage unavailable');
    await submit().trigger('click');
    expect(wrapper.emitted('submit')[0][0].images).toHaveLength(1);
    await wrapper.vm.discard();
    expect(wrapper.findAll('.ProseMirror img[src^="blob:"]')).toHaveLength(0);
  });
});
