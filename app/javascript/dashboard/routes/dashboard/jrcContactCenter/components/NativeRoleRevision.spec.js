import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import roleLocale from 'dashboard/i18n/locale/en/customRole.json';
import contactCenterLocale from 'dashboard/i18n/locale/en/jrcContactCenter.json';
import NativeRoleEditor from './NativeRoleEditor.vue';
import Modal from 'dashboard/routes/dashboard/settings/customRoles/component/CustomRoleModal.vue';
import CustomRoleAPI from 'dashboard/api/customRole';
import { useAlert } from 'dashboard/composables';

const { store } = vi.hoisted(() => ({
  store: { getters: {}, dispatch: vi.fn(), commit: vi.fn() },
}));
vi.mock('dashboard/composables/store', () => ({ useStore: () => store }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/customRole', () => ({ default: { show: vi.fn() } }));
enableAutoUnmount(afterEach);
const role = {
  id: 7,
  name: 'Synthetic profile',
  description: 'Original',
  permissions: ['jrc_contact_center_view'],
  revision: 'original-version',
};
const global = {
  plugins: [
    createI18n({
      legacy: false,
      locale: 'en',
      messages: { en: { ...roleLocale, ...contactCenterLocale } },
    }),
  ],
  stubs: {
    WootModalHeader: true,
    Button: {
      props: ['label', 'disabled', 'type'],
      template:
        '<button :type="type" :disabled="disabled">{{ label }}</button>',
    },
  },
};
beforeEach(() => {
  vi.clearAllMocks();
  store.dispatch.mockResolvedValue({});
  store.getters = {
    getCurrentAccountId: 1,
    'accounts/isFeatureEnabledonAccount': (_, flag) =>
      flag === 'jrc_contact_center',
    'customRole/getUIFlags': {},
  };
});

it('sends the captured version only after explicit Call Center review', async () => {
  const wrapper = mount(NativeRoleEditor, {
    props: { roles: [role], selectedRole: role },
    global,
  });
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  expect(store.dispatch).not.toHaveBeenCalled();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(store.dispatch).toHaveBeenCalledWith('customRole/updateCustomRole', {
    id: 7,
    name: role.name,
    description: role.description,
    permissions: role.permissions,
    expected_revision: 'original-version',
  });
});

it('preserves a stale draft and requires loading and reviewing the new server version', async () => {
  store.dispatch.mockRejectedValueOnce(new Error('stale_role_revision'));
  CustomRoleAPI.show.mockResolvedValueOnce({
    data: {
      ...role,
      name: 'Concurrent profile',
      description: 'New server state',
      revision: 'fresh-version',
    },
  });
  const wrapper = mount(NativeRoleEditor, {
    props: { roles: [role], selectedRole: role },
    global,
  });
  await flushPromises();
  await wrapper.get('input[type="text"]').setValue('My retained draft');
  await wrapper.get('textarea').setValue('Retained description');
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(wrapper.get('[data-role-conflict]').text()).toContain('outra sessão');
  expect(wrapper.get('input[type="text"]').element.value).toBe(
    'My retained draft'
  );
  expect(wrapper.get('textarea').element.value).toBe('Retained description');
  expect(wrapper.find('[data-role-review]').exists()).toBe(false);
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
  await wrapper.get('[data-role-conflict] button').trigger('click');
  await flushPromises();
  expect(CustomRoleAPI.show).toHaveBeenCalledWith(7);
  expect(wrapper.get('[data-role-latest]').text()).toContain(
    'New server state'
  );
  expect(wrapper.get('input[type="text"]').element.value).toBe(
    'My retained draft'
  );
  await wrapper.get('form').trigger('submit');
  expect(store.dispatch).toHaveBeenCalledTimes(1);
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(store.dispatch).toHaveBeenLastCalledWith(
    'customRole/updateCustomRole',
    expect.objectContaining({
      name: 'My retained draft',
      description: 'Retained description',
      expected_revision: 'fresh-version',
    })
  );
});

it('keeps a failed reload blocked and preserves the fields for recovery', async () => {
  store.dispatch.mockRejectedValueOnce(new Error('stale_role_revision'));
  CustomRoleAPI.show.mockRejectedValueOnce(new Error('Unavailable'));
  const wrapper = mount(NativeRoleEditor, {
    props: { roles: [role], selectedRole: role },
    global,
  });
  await flushPromises();
  await wrapper.get('textarea').setValue('Do not discard');
  await wrapper.get('form').trigger('submit');
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  await wrapper.get('[data-role-conflict] button').trigger('click');
  await flushPromises();
  expect(wrapper.get('textarea').element.value).toBe('Do not discard');
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
  expect(useAlert).toHaveBeenLastCalledWith(
    expect.stringContaining('Não foi possível carregar')
  );
});

it('does not silently downgrade a Call Center editor whose API response lacks a revision', async () => {
  const selectedRole = { ...role, revision: undefined };
  const wrapper = mount(NativeRoleEditor, {
    props: { roles: [selectedRole], selectedRole },
    global,
  });
  await flushPromises();
  expect(wrapper.get('[data-role-conflict]').text()).toContain('versão');
  expect(wrapper.get('button[type="submit"]').element.disabled).toBe(true);
  await wrapper.get('form').trigger('submit');
  expect(store.dispatch).not.toHaveBeenCalled();
});

it('preserves the payload contract of native editors that do not opt into revisions', async () => {
  const wrapper = mount(Modal, {
    props: { mode: 'edit', selectedRole: role },
    global,
  });
  await flushPromises();
  await wrapper.get('form').trigger('submit');
  await flushPromises();
  expect(store.dispatch).toHaveBeenCalledWith('customRole/updateCustomRole', {
    id: 7,
    name: role.name,
    description: role.description,
    permissions: role.permissions,
  });
});
