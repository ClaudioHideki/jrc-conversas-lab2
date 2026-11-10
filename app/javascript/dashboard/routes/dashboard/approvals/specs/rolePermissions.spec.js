import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { beforeEach, expect, it, vi } from 'vitest';
import locale from 'dashboard/i18n/locale/en/customRole.json';
import Modal from 'dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue';
const { store } = vi.hoisted(() => ({
  store: { getters: {}, dispatch: vi.fn() },
}));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const options = role => ({
  props: { mode: 'edit', selectedRole: role },
  global: {
    plugins: [
      createI18n({ legacy: false, locale: 'en', messages: { en: locale } }),
    ],
    stubs: {
      Button: {
        props: ['label', 'disabled', 'type'],
        template:
          '<button :type="type" :disabled="disabled">{{ label }}</button>',
      },
    },
  },
});
beforeEach(() => {
  store.dispatch.mockReset();
  store.dispatch.mockResolvedValue({});
  store.getters = {
    getCurrentAccountId: 1,
    'accounts/isFeatureEnabledonAccount': (_, flag) => flag === 'jrc_approvals',
  };
});
it('offers explicit approval capabilities without automatically adding decision or native module access', async () => {
  const wrapper = mount(
    Modal,
    options({
      id: 7,
      name: 'Synthetic existing role',
      description: 'Synthetic',
      permissions: ['contact_manage'],
    })
  );
  await flushPromises();
  expect(wrapper.find('#jrc_approvals_adjust').exists()).toBe(true);
  await wrapper.find('#jrc_approvals_adjust').setValue(true);
  expect(wrapper.find('#jrc_approvals_decide').element.checked).toBe(false);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(store.dispatch).toHaveBeenCalledWith(
    'customRole/updateCustomRole',
    expect.objectContaining({
      permissions: ['contact_manage', 'jrc_approvals_adjust'],
    })
  );
  wrapper.unmount();
});
it('hides disabled feature controls while preserving existing role permissions on save', async () => {
  store.getters['accounts/isFeatureEnabledonAccount'] = () => false;
  const wrapper = mount(
    Modal,
    options({
      id: 7,
      name: 'Synthetic preserved role',
      description: 'Synthetic',
      permissions: ['contact_manage', 'jrc_approvals_adjust'],
    })
  );
  await flushPromises();
  expect(wrapper.find('#jrc_approvals_adjust').exists()).toBe(false);
  await wrapper.find('form').trigger('submit');
  await flushPromises();
  expect(store.dispatch).toHaveBeenCalledWith(
    'customRole/updateCustomRole',
    expect.objectContaining({
      permissions: ['contact_manage', 'jrc_approvals_adjust'],
    })
  );
  wrapper.unmount();
});
