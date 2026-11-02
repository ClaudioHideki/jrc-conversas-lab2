import { mount } from '@vue/test-utils';
import Dialog from '../../dialog/Dialog.vue';

let wrapper;
afterEach(() => wrapper?.unmount());

it('gives the actual native dialog its configured accessible name', async () => {
  wrapper = mount(Dialog, {
    props: { title: 'WhatsApp connection details', useForm: false },
    global: {
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    },
  });
  wrapper.get('dialog').element.close = vi.fn();
  expect(wrapper.get('dialog').attributes('aria-label')).toBe(
    'WhatsApp connection details'
  );
  await wrapper.setProps({ title: 'Reconnect WhatsApp' });
  expect(wrapper.get('dialog').attributes('aria-label')).toBe(
    'Reconnect WhatsApp'
  );
});

it('does not invent a name when a caller supplies its own heading', () => {
  wrapper = mount(Dialog, {
    props: { useForm: false },
    global: {
      stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
    },
  });
  wrapper.get('dialog').element.close = vi.fn();
  expect(wrapper.get('dialog').attributes('aria-label')).toBeUndefined();
});
