import { mount, flushPromises } from '@vue/test-utils';
import { reactive } from 'vue';
import CrmLayout from '../CrmLayout.vue';

const mocks = vi.hoisted(() => ({ route: null, getters: null }));
vi.mock('vue-router', () => ({ useRoute: () => mocks.route }));
vi.mock('vuex', () => ({ useStore: () => ({ getters: mocks.getters }) }));

const destinations = [
  'crm_dashboard',
  'crm_indicators',
  'crm_leads',
  'crm_deals',
  'crm_funnel',
  'crm_wallet',
  'crm_products',
  'crm_proposals',
  'crm_orders',
  'crm_contracts',
  'crm_activities',
  'crm_calendar',
  'crm_goals',
  'crm_commissions',
  'crm_management',
  'crm_settings',
];

describe('CRM module navigation', () => {
  let wrapper;
  beforeEach(() => {
    mocks.route = reactive({
      name: 'crm_dashboard',
      params: { accountId: '1' },
    });
    mocks.getters = reactive({ getCurrentRole: 'administrator' });
    wrapper = mount(CrmLayout, {
      global: {
        stubs: {
          RouterLink: {
            props: ['to'],
            template: '<a :href="to.name" @click.prevent><slot /></a>',
          },
          RouterView: true,
        },
      },
    });
  });
  afterEach(() => wrapper.unmount());

  it.each(destinations)(
    'selects %s after a route change and closes the open group',
    async name => {
      expect(wrapper.get('[aria-current="page"]').attributes('href')).toBe(
        'crm_dashboard'
      );
      mocks.route.name = name === 'crm_orders' ? 'crm_dashboard' : 'crm_orders';
      await flushPromises();
      wrapper.findAll('details').forEach(menu => {
        menu.element.open = true;
      });
      mocks.route.name = name;
      await flushPromises();
      expect(wrapper.findAll('[aria-current="page"]')).toHaveLength(1);
      expect(wrapper.get('[aria-current="page"]').attributes('href')).toBe(
        name
      );
      expect(wrapper.findAll('details[open]')).toHaveLength(0);
      const active = wrapper.get(`[href="${name}"]`);
      if (active.element.closest('details')) {
        expect(
          active.element.closest('details').querySelector('summary').classList
        ).toContain('shadow-sm');
      }
    }
  );

  it.each([
    ['crm_order_new', 'crm_orders'],
    ['crm_contract_new', 'crm_contracts'],
    ['crm_contract_templates', 'crm_contracts'],
  ])('keeps the parent selected for %s', async (name, parent) => {
    mocks.route.name = name;
    await flushPromises();
    expect(wrapper.get('[aria-current="page"]').attributes('href')).toBe(
      parent
    );
  });

  it('exposes all tabs once through wrapping primary tabs and native groups', () => {
    const nav = wrapper.get('nav');
    expect(nav.classes()).toContain('flex-wrap');
    expect(nav.attributes('aria-label')).toBeTruthy();
    expect(nav.findAll(':scope > a')).toHaveLength(5);
    expect(nav.findAll('details')).toHaveLength(3);
    expect(
      nav
        .findAll('a')
        .map(link => link.attributes('href'))
        .sort()
    ).toEqual([...destinations].sort());
  });

  it.each([0, 1, 2])('closes group %i on selection or Escape', async index => {
    const menu = wrapper.findAll('nav details')[index];
    expect(menu.get('summary').text()).toBeTruthy();
    menu.element.open = true;
    await menu.findAll('a')[0].trigger('click');
    expect(menu.element.open).toBe(false);
    menu.element.open = true;
    await menu.get('summary').trigger('keydown', { key: 'Escape' });
    expect(menu.element.open).toBe(false);
  });

  it('reacts to revoked administrator access without leaving empty management menus', async () => {
    mocks.getters.getCurrentRole = 'agent';
    await flushPromises();
    const nav = wrapper.get('nav');
    expect(nav.find('[href="crm_management"]').exists()).toBe(false);
    expect(nav.find('[href="crm_settings"]').exists()).toBe(false);
    expect(nav.findAll('details')).toHaveLength(2);
    expect(
      nav
        .findAll('a')
        .map(link => link.attributes('href'))
        .sort()
    ).toEqual(
      destinations
        .filter(name => !['crm_management', 'crm_settings'].includes(name))
        .sort()
    );
  });
});
