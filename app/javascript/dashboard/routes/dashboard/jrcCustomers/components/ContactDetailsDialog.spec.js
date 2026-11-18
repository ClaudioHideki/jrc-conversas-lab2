import { afterEach, describe, expect, it, vi } from 'vitest';
import { defineComponent } from 'vue';
import { enableAutoUnmount, mount, RouterLinkStub } from '@vue/test-utils';
import ContactDetailsDialog from './ContactDetailsDialog.vue';
import Contact360Panel from './Contact360Panel.vue';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('../useCustomerMaster', () => ({
  useCustomerMaster: () => ({
    accountScopedRoute: (name, params) => ({
      name,
      params: { accountId: 1, ...params },
    }),
  }),
}));
const Dialog = defineComponent({
  setup(_props, { expose }) {
    expose({ open: vi.fn() });
  },
  template: '<section><slot /></section>',
});

const render = (props = {}) =>
  mount(ContactDetailsDialog, {
    props: { contactId: '2', ...props },
    global: {
      stubs: { Dialog, Contact360Panel: true, RouterLink: RouterLinkStub },
    },
  });
enableAutoUnmount(afterEach);

describe('native contact dialog full-page target', () => {
  it('preserves same-page navigation for existing callers by default', () => {
    const wrapper = render();
    const link = wrapper.findComponent(RouterLinkStub);
    expect(link.props('to')).toEqual({
      name: 'contacts_edit',
      params: { accountId: 1, contactId: '2' },
    });
    expect(link.attributes('target')).toBeUndefined();
    expect(link.attributes('rel')).toBeUndefined();
    expect(wrapper.getComponent(Contact360Panel).props('contactId')).toBe('2');
  });
  it('lets an attendance caller opt into an independent page without changing the native contact route', () => {
    const wrapper = render({ openFullPageInNewTab: true });
    const link = wrapper.findComponent(RouterLinkStub);
    expect(link.props('to')).toEqual({
      name: 'contacts_edit',
      params: { accountId: 1, contactId: '2' },
    });
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });
});
