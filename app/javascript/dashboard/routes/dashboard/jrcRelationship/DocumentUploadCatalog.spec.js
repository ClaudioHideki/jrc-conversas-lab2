import { mount, flushPromises } from '@vue/test-utils';
import { expect, it, vi } from 'vitest';
import Upload from './DocumentUploadDialog.vue';
import Field from './DocumentRequirementField.vue';
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
const Dialog = {
  setup(_, { expose }) {
    expose({ open: vi.fn(), close: vi.fn() });
  },
  template: '<section><slot /></section>',
};
const entries = [
  { code: 'proof', title: 'Registration proof', category: 'registration' },
];
it('submits an explicit requirement with the native file upload and clears a stale choice when category changes', async () => {
  const wrapper = mount(Upload, {
    props: { requirements: entries },
    global: { stubs: { Dialog } },
  });
  await flushPromises();
  await wrapper.getComponent(Field).get('select').setValue('proof');
  const file = new File(['Synthetic'], 'synthetic.txt', { type: 'text/plain' });
  const input = wrapper.get('input[type="file"]');
  Object.defineProperty(input.element, 'files', { value: [file] });
  await input.trigger('change');
  await wrapper.get('form').trigger('submit');
  expect(wrapper.emitted('save')[0][0]).toEqual(
    expect.objectContaining({ requirement_key: 'proof', file })
  );
  await wrapper.findAll('select')[0].setValue('contract');
  expect(wrapper.getComponent(Field).props('modelValue')).toBe('');
  wrapper.unmount();
});
it('preserves the existing document identity and hides requirement remapping during a file-version upload', async () => {
  const wrapper = mount(Upload, {
    props: {
      document: {
        id: 6,
        title: 'Previous evidence',
        category: 'registration',
        requirement_key: 'old_code',
      },
      requirements: entries,
    },
    global: { stubs: { Dialog } },
  });
  await flushPromises();
  expect(wrapper.findComponent(Field).exists()).toBe(false);
  expect(wrapper.get('select').element.disabled).toBe(true);
  expect(wrapper.get('input[maxlength="160"]').element.disabled).toBe(true);
  wrapper.unmount();
});
