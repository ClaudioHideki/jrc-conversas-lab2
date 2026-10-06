import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import SidebarGroupHeader from '../SidebarGroupHeader.vue';
import SidebarUniversity from '../SidebarUniversity.vue';
import { withNewBadge } from '../newModules';
vi.mock('dashboard/composables/store.js', () => ({
  useMapGetter: () => ref(false),
}));
describe('Requested new module badges', () => {
  it.each([
    'JRC AI Agents',
    'JRC AI Insights',
    'JRC Intelligent Automation',
    'Customers',
    'Relationship',
    'JRC Projects',
    'JRC Agenda',
    'JRC Service Desk Structure',
    'JRC AI Administration',
  ])('marks %s without changing navigation or access', name => {
    const item = { name, to: { name: 'route' }, disabled: true, children: [] };
    expect(withNewBadge(item)).toEqual({ ...item, newBadge: true });
    expect(item.newBadge).toBeUndefined();
  });
  it('preserves CRM/Campaigns badges and leaves unrelated modules unchanged', () => {
    expect(withNewBadge({ name: 'CRM', newBadge: true }).newBadge).toBe(true);
    expect(withNewBadge({ name: 'Reports' }).newBadge).toBe(false);
  });
  it.each([false, true])(
    'reserves the same trailing column with expandable=%s',
    expandable => {
      const w = mount(SidebarGroupHeader, {
        props: { label: 'Module', newBadge: true, expandable },
      });
      expect(w.get('[data-testid="sidebar-new-badge"]').text()).toBe('Novo');
      expect(
        w.get('[data-testid="sidebar-trailing-slot"]').classes()
      ).toContain('size-3');
      expect(w.find('.i-lucide-chevron-down').exists()).toBe(expandable);
    }
  );
  it('keeps the university badge aligned and hides it in compact mode', async () => {
    const w = mount(SidebarUniversity);
    expect(w.get('[data-testid="sidebar-trailing-slot"]').classes()).toContain(
      'size-3'
    );
    expect(w.find('[data-testid="sidebar-new-badge"]').exists()).toBe(true);
    await w.setProps({ collapsed: true });
    expect(w.find('[data-testid="sidebar-new-badge"]').exists()).toBe(false);
    expect(w.get('a').attributes('aria-label')).toBe('UniversidadeJRC');
  });
});
