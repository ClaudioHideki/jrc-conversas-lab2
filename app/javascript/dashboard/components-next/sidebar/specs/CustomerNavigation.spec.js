import { runInNewContext } from 'node:vm';
import { babelParse } from '@vue/compiler-sfc';
import { ref } from 'vue';
import { mount } from '@vue/test-utils';
import sidebarSource from '../Sidebar.vue?raw';
import { visibleSidebarSections } from '../temporaryVisibility';
import { universityLink } from '../university';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { routes } from 'dashboard/routes/dashboard/jrcCustomers/routes';
import Policy from 'dashboard/components/policy.vue';

const state = vi.hoisted(() => ({ user: null, enabled: true }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: key => {
    if (key === 'getCurrentUser') return ref(state.user);
    if (key === 'accounts/isFeatureEnabledonAccount') {
      return ref(() => state.enabled);
    }
    return ref(false);
  },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountId: ref(1) }),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false }),
}));

// Evaluate the actual composers, including the feature condition. This catches
// an item being granted in menuItems but lost before menuSections is rendered.
const source = sidebarSource.split('<script setup>')[1].split('</script>')[0];
const declarations = babelParse(source, { sourceType: 'module' }).program.body;
const declaration = name =>
  declarations.find(row => row.declarations?.[0]?.id.name === name);
const menu = declaration('menuItems').declarations[0].init.arguments[0];
const returned = menu.body.body.find(row => row.type === 'ReturnStatement');
const customer = returned.argument.callee.object.callee.object.elements.find(
  row =>
    row.type === 'ConditionalExpression' &&
    source.slice(row.test.start, row.test.end) === 'hasCustomerMaster.value'
);
const flag = declaration('hasCustomerMaster');
const composer = declaration('menuSections');
const context = enabled => ({
  computed: callback => ({ value: callback() }),
  accountId: { value: 1 },
  FEATURE_FLAGS,
  isFeatureEnabledonAccount: {
    value: (accountId, feature) =>
      accountId === 1 &&
      feature === FEATURE_FLAGS.JRC_CUSTOMER_MASTER &&
      enabled,
  },
  accountScopedRoute: name => ({ name, params: { accountId: 1 } }),
  contactsModule: { name: 'Contacts' },
});
const customerItem = enabled =>
  runInNewContext(
    `${source.slice(flag.start, flag.end)}; (${source.slice(customer.start, customer.end)})`,
    context(enabled)
  );
const sections = (enabled, unified) =>
  runInNewContext(
    `${source.slice(composer.start, composer.end)}; menuSections.value`,
    {
      computed: callback => ({ value: callback() }),
      menuItems: {
        value: [
          { name: 'CRM' },
          customerItem(enabled),
          { name: 'Relationship' },
        ],
      },
      legacyMenuItems: { value: [] },
      useUnifiedAttendanceNavigation: { value: unified },
      visibleSidebarSections,
      universityLink,
      t: key => key,
    }
  );

describe('Clientes navigation in the final sidebar', () => {
  it.each([
    [true, 'crm'],
    [false, 'relationships'],
  ])('keeps Clientes exactly once with unified=%s', (unified, sectionName) => {
    const result = sections(true, unified);
    const customers = result
      .flatMap(section => section.items)
      .filter(item => item.name === 'Customers');
    expect(customers).toHaveLength(1);
    expect(
      result.find(section => section.name === sectionName).items
    ).toContainEqual(customers[0]);
    expect(customers[0].to.params.accountId).toBe(1);
  });

  it.each([true, false])(
    'respects the feature gate with unified=%s',
    unified => {
      expect(
        sections(false, unified)
          .flatMap(section => section.items)
          .some(item => item.name === 'Customers')
      ).toBe(false);
      expect(customerItem(false).name).toBe('Contacts');
    }
  );

  it('preserves all six submenu destinations and the other CRM items', () => {
    const result = sections(true, true).find(section => section.name === 'crm');
    expect(result.items.map(item => item.name)).toEqual([
      'CRM',
      'Customers',
      'Relationship',
    ]);
    expect(
      result.items[1].children.map(item => [item.label, item.to.name])
    ).toEqual([
      ['Empresas', 'jrc_customer_companies'],
      ['Contatos', 'contacts_dashboard_index'],
      ['Segmentos', 'jrc_customer_segments'],
      ['Grupos', 'jrc_customer_groups'],
      ['Importações', 'jrc_customer_imports'],
      ['Contatos ativos', 'contacts_dashboard_active'],
    ]);
  });

  it.each([101, 102])(
    'keeps the existing route policy for local administrator %s',
    id => {
      state.user = {
        id,
        accounts: [{ id: 1, permissions: ['administrator'] }],
      };
      routes.forEach(route => {
        const wrapper = mount(Policy, {
          props: { permissions: route.meta.permissions },
          slots: { default: 'Clientes' },
        });
        expect(wrapper.text()).toBe('Clientes');
        wrapper.unmount();
      });
    }
  );

  it.each([
    [{ id: 1, permissions: [] }],
    [{ id: 2, permissions: ['administrator'] }],
  ])(
    'does not grant access without permission in the current Account: %j',
    account => {
      state.user = { accounts: [account] };
      routes.forEach(route => {
        const wrapper = mount(Policy, {
          props: { permissions: route.meta.permissions },
          slots: { default: 'Clientes' },
        });
        expect(wrapper.text()).toBe('');
        wrapper.unmount();
      });
    }
  );
});
