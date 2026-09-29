import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import { createRouter, createMemoryHistory } from 'vue-router';
import { provideSidebarContext } from '../provider';
import SidebarGroup from '../SidebarGroup.vue';

vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ref(false),
}));
vi.mock('dashboard/composables/usePolicy', () => ({
  usePolicy: () => ({ shouldShow: () => true }),
}));

const pages = [
  { path: '/conversations', name: 'conversations' },
  { path: '/crm', name: 'crm' },
  { path: '/crm/funnel', name: 'funnel' },
];
const children = [
  { name: 'overview', label: 'Overview', to: { name: 'crm' } },
  { name: 'funnel', label: 'Funnel', to: { name: 'funnel' } },
];

describe('sidebar group navigation', () => {
  it.each(['header', 'chevron'])(
    'collapses CRM using %s without navigating or leaving an orphan child',
    async target => {
      const router = createRouter({
        history: createMemoryHistory(),
        routes: pages.map(page => ({
          ...page,
          component: { template: '<div />' },
        })),
      });
      await router.push('/crm/funnel');
      const expandedItem = ref(null);
      const wrapper = mount(
        {
          components: { SidebarGroup },
          setup() {
            provideSidebarContext({
              expandedItem,
              setExpandedItem: name => {
                expandedItem.value = expandedItem.value === name ? null : name;
              },
              isCollapsed: ref(false),
              isResizing: ref(false),
            });
            return { children };
          },
          template:
            '<SidebarGroup name="CRM" label="CRM" :to="{name: \'crm\'}" :children="children" />',
        },
        {
          global: {
            plugins: [router],
            stubs: { Policy: { template: '<li><slot /></li>' } },
          },
        }
      );
      await flushPromises();
      const push = vi.spyOn(router, 'push');
      const header = wrapper.find('button[title="CRM"]');
      expect(header.attributes('aria-expanded')).toBe('true');
      await (
        target === 'header' ? header : header.find('.i-lucide-chevron-down')
      ).trigger('click');
      await flushPromises();
      expect(push).not.toHaveBeenCalled();
      expect(router.currentRoute.value.fullPath).toBe('/crm/funnel');
      expect(header.attributes('aria-expanded')).toBe('false');
      expect(
        wrapper.find('a[href="/crm/funnel"]').element.closest('ul').style
          .display
      ).toBe('none');
      await header.trigger('click');
      await flushPromises();
      expect(header.attributes('aria-expanded')).toBe('true');
      expect(
        wrapper.find('a[href="/crm/funnel"]').element.closest('ul').style
          .display
      ).not.toBe('none');
      expect(push).not.toHaveBeenCalled();
      await header.trigger('click');
      await router.push('/conversations');
      await router.push('/crm/funnel');
      await flushPromises();
      expect(header.attributes('aria-expanded')).toBe('true');
      wrapper.unmount();
    }
  );

  it('opens another group with exactly one navigation', async () => {
    const router = createRouter({
      history: createMemoryHistory(),
      routes: pages.map(page => ({
        ...page,
        component: { template: '<div />' },
      })),
    });
    await router.push('/conversations');
    const expandedItem = ref(null);
    const wrapper = mount(
      {
        components: { SidebarGroup },
        setup() {
          provideSidebarContext({
            expandedItem,
            setExpandedItem: name => {
              expandedItem.value = expandedItem.value === name ? null : name;
            },
            isCollapsed: ref(false),
            isResizing: ref(false),
          });
          return { children };
        },
        template:
          '<SidebarGroup name="CRM" label="CRM" :to="{name: \'crm\'}" :children="children" />',
      },
      {
        global: {
          plugins: [router],
          stubs: { Policy: { template: '<li><slot /></li>' } },
        },
      }
    );
    await flushPromises();
    const push = vi.spyOn(router, 'push');
    await wrapper.find('button[title="CRM"]').trigger('click');
    await flushPromises();
    expect(push).toHaveBeenCalledTimes(1);
    expect(router.currentRoute.value.name).toBe('crm');
    wrapper.unmount();
  });

  it.each([false, true])(
    'keeps compact disabled=%s items legible and respects availability',
    async disabled => {
      const router = createRouter({
        history: createMemoryHistory(),
        routes: pages.map(page => ({
          ...page,
          component: { template: '<div />' },
        })),
      });
      await router.push('/conversations');
      const wrapper = mount(
        {
          components: { SidebarGroup },
          setup() {
            provideSidebarContext({
              expandedItem: ref(null),
              setExpandedItem: vi.fn(),
              isCollapsed: ref(true),
              isResizing: ref(false),
            });
            return { disabled, children };
          },
          template:
            '<SidebarGroup name="CRM" label="CRM" :disabled="disabled" :to="{name: \'crm\'}" :children="children" />',
        },
        {
          global: {
            plugins: [router],
            stubs: { Policy: { template: '<li><slot /></li>' } },
          },
        }
      );
      await flushPromises();
      const push = vi.spyOn(router, 'push');
      const trigger = wrapper.find('button[title="CRM"]');
      expect(trigger.classes()).toContain(
        disabled ? 'text-sidebar-muted' : 'text-sidebar-foreground'
      );
      expect(trigger.classes()).not.toContain('opacity-60');
      await trigger.trigger('click');
      await flushPromises();
      expect(push).toHaveBeenCalledTimes(disabled ? 0 : 1);
      wrapper.unmount();
    }
  );
});
