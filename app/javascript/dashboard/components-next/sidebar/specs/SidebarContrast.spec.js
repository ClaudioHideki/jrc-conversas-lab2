import { mount } from '@vue/test-utils';
import { h, ref } from 'vue';
import { colors } from '../../../../../../theme/colors';
import SidebarGroupSeparator from '../SidebarGroupSeparator.vue';
import SidebarGroupLeaf from '../SidebarGroupLeaf.vue';
import SidebarGroupHeader from '../SidebarGroupHeader.vue';

vi.mock('../provider', () => ({
  useSidebarContext: () => ({
    resolvePermissions: () => [],
    resolveFeatureFlag: () => '',
  }),
}));
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ref(false),
}));

describe('sidebar palette and shared navigation components', () => {
  it('keeps readable foregrounds on the fixed navy surface in either theme', () => {
    const luminance = hex => {
      const rgb = hex.match(/[a-f\d]{2}/gi).map(value => {
        const channel = parseInt(value, 16) / 255;
        return channel <= 0.04045
          ? channel / 12.92
          : ((channel + 0.055) / 1.055) ** 2.4;
      });
      return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
    };
    ['foreground', 'secondary', 'muted'].forEach(token => {
      const ratio =
        (luminance(colors.sidebar[token]) + 0.05) /
        (luminance(colors.sidebar.surface) + 0.05);
      expect(ratio).toBeGreaterThanOrEqual(4.5);
    });
    expect(
      (luminance(colors.sidebar.foreground) + 0.05) /
        (luminance(colors.sidebar.active) + 0.05)
    ).toBeGreaterThanOrEqual(4.5);
  });

  it.each([false, true])(
    'styles group labels, icons and chevrons with expanded=%s',
    async expanded => {
      const wrapper = mount(SidebarGroupSeparator, {
        props: {
          label: 'Qualquer grupo',
          icon: 'i-lucide-users',
          collapsible: true,
          isExpanded: expanded,
        },
      });
      const buttons = wrapper.findAll('button');
      buttons.forEach(button => {
        expect(button.classes()).toContain('text-sidebar-secondary');
        expect(button.attributes('aria-expanded')).toBe(String(expanded));
      });
      expect(wrapper.find('.i-lucide-users').exists()).toBe(true);
      await buttons[0].trigger('click');
      expect(wrapper.emitted('toggle')).toHaveLength(1);
      wrapper.unmount();
    }
  );

  it.each([false, true])(
    'preserves label dot color and selected state active=%s',
    active => {
      const wrapper = mount(SidebarGroupLeaf, {
        props: {
          label: 'Etiqueta',
          to: '/labels/test',
          active,
          icon: h('span', {
            'data-label-dot': '',
            style: { backgroundColor: '#d946ef' },
          }),
        },
        global: {
          stubs: {
            Policy: { template: '<li><slot /></li>' },
            RouterLink: { template: '<a><slot /></a>' },
          },
        },
      });
      expect(wrapper.find('a').classes()).toContain('text-sidebar-secondary');
      expect(wrapper.find('a').classes().includes('bg-sidebar-active')).toBe(
        active
      );
      expect(
        wrapper.find('[data-label-dot]').element.style.backgroundColor
      ).toBe('rgb(217, 70, 239)');
      wrapper.unmount();
    }
  );

  it('keeps primary and child hierarchy and the selected blue background', async () => {
    const wrapper = mount(SidebarGroupHeader, {
      props: { label: 'Conversas', icon: 'i-lucide-message-circle' },
    });
    expect(wrapper.classes()).toContain('text-sidebar-foreground');
    await wrapper.setProps({ isActive: true });
    expect(wrapper.classes()).toContain('bg-sidebar-active');
    wrapper.unmount();
  });
});
