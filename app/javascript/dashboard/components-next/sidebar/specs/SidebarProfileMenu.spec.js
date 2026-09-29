import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidebarProfileMenu from '../SidebarProfileMenu.vue';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key =>
    ref(
      {
        getCurrentUser: {
          available_name: 'Nome real',
          email: 'pessoa@example.test',
        },
        getCurrentUserAvailability: 'online',
        getCurrentAccountId: 1,
        'globalConfig/get': {},
        'accounts/isFeatureEnabledonAccount': () => false,
      }[key]
    ),
}));
vi.mock('dashboard/composables/useImpersonation', () => ({
  useImpersonation: () => ({ isImpersonating: ref(false) }),
}));
vi.mock('dashboard/api/auth', () => ({ default: { logout: vi.fn() } }));

describe('sidebar profile presentation', () => {
  it.each([false, true])('preserves identity with collapsed=%s', collapsed => {
    const wrapper = mount(SidebarProfileMenu, {
      props: { isCollapsed: collapsed },
      global: {
        stubs: {
          DropdownContainer: {
            template:
              '<div><slot name="trigger" :toggle="() => {}" :isOpen="false" /></div>',
          },
          DropdownBody: true,
          Avatar: true,
        },
      },
    });
    if (collapsed) {
      expect(wrapper.find('button').attributes('title')).toBe('Nome real');
      expect(wrapper.text()).not.toContain('pessoa@example.test');
    } else {
      expect(wrapper.text()).toBe('Nome realpessoa@example.test');
      expect(wrapper.find('.font-semibold').classes()).toContain(
        '!text-sidebar-foreground'
      );
      expect(wrapper.find('.text-xs').classes()).toContain(
        '!text-sidebar-secondary'
      );
    }
    wrapper.unmount();
  });
});
