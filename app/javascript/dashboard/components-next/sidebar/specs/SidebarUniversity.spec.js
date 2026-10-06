import { mount } from '@vue/test-utils';
import SidebarUniversity from '../SidebarUniversity.vue';
import { universityLink } from '../university';
import { visibleSidebarSections } from '../temporaryVisibility';

describe('UniversidadeJRC public navigation', () => {
  it.each(['administrator', 'agent', 'custom_role'])(
    'is a safe external link for %s without an account permission gate',
    role => {
      const wrapper = mount(SidebarUniversity, {
        global: { provide: { role } },
      });
      const link = wrapper.get('a');
      expect(link.text()).toContain('UniversidadeJRC');
      expect(wrapper.find('[data-testid="sidebar-new-badge"]').text()).toBe(
        'Novo'
      );
      expect(link.attributes('href')).toBe(
        'https://universidadejrc.com.br/portal/layout/910/treynando/login_inicial.asp?V29ya3NwYWNlSUQ9MTQwMCZrdF9kaWRheGlzPXRvcA'
      );
      expect(link.attributes('target')).toBe('_blank');
      expect(link.attributes('rel')).toBe('noopener noreferrer');
      expect(link.classes()).toContain(
        'focus-visible:outline-sidebar-foreground'
      );
    }
  );
  it('keeps an accessible name in compact mode', () => {
    const wrapper = mount(SidebarUniversity, { props: { collapsed: true } });
    expect(wrapper.get('a').attributes('aria-label')).toBe('UniversidadeJRC');
    expect(wrapper.get('a').attributes('title')).toBe('UniversidadeJRC');
    expect(wrapper.get('a').classes()).toContain('size-10');
  });
  it('preserves hidden legacy entries and the other modules', () => {
    const items = ['Calls', 'Campaigns', 'Portals', 'CRM', 'JRC Campaigns'].map(
      name => ({ name })
    );
    const sections = visibleSidebarSections([
      { items },
      { items: [universityLink] },
    ]);
    expect(sections[0].items.map(item => item.name)).toEqual([
      'CRM',
      'JRC Campaigns',
    ]);
    expect(sections[1].items).toEqual([universityLink]);
  });
});
