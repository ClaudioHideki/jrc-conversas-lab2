import { runInNewContext } from 'node:vm';
import { babelParse } from '@vue/compiler-sfc';
import sidebarSource from '../Sidebar.vue?raw';
import { visibleSidebarSections } from '../temporaryVisibility';
import { universityLink } from '../university';

const source = sidebarSource.split('<script setup>')[1].split('</script>')[0];
const declarations = babelParse(source, { sourceType: 'module' }).program.body;
const declaration = name =>
  declarations.find(row => row.declarations?.[0]?.id.name === name);
const menu = declaration('menuItems').declarations[0].init.arguments[0];
const returned = menu.body.body.find(row => row.type === 'ReturnStatement');
const objects = returned.argument.callee.object.callee.object.elements;
const backoffice = objects.find(
  row =>
    row.type === 'ObjectExpression' &&
    row.properties.some(
      property =>
        property.key.name === 'name' && property.value.value === 'Backoffice'
    )
);
const composer = declaration('menuSections');
const item = (enabled = true, permitted = true) =>
  runInNewContext(`(${source.slice(backoffice.start, backoffice.end)})`, {
    t: key => key,
    accountScopedRoute: name => ({ name, params: { accountId: 1 } }),
    hasJrcCrm: { value: enabled },
    hasCrmUserAccess: { value: permitted },
  });

it.each([true, false])(
  'places Backoffice once immediately below CRM in unified=%s',
  unified => {
    const result = runInNewContext(
      `${source.slice(composer.start, composer.end)}; menuSections.value`,
      {
        computed: callback => ({ value: callback() }),
        menuItems: {
          value: [
            { name: 'CRM' },
            item(),
            { name: 'Customers' },
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
    const names = result.flatMap(section => section.items.map(row => row.name));
    expect(names.filter(name => name === 'Backoffice')).toHaveLength(1);
    expect(names.indexOf('Backoffice')).toBe(names.indexOf('CRM') + 1);
    expect(item().activeOn).toContain('crm_backoffice_request');
    expect(item().activeOn).toContain('crm_backoffice_new');
  }
);

it.each([
  [false, true],
  [true, false],
])(
  'keeps the CRM feature and permission gate: %s/%s',
  (feature, permission) => {
    expect(item(feature, permission).disabled).toBe(true);
  }
);

it('keeps CRM as a single module entry, with its internal destinations in horizontal tabs', () => {
  const crm = objects.find(
    row =>
      row.type === 'ObjectExpression' &&
      row.properties.some(
        property =>
          property.key.name === 'name' && property.value.value === 'CRM'
      )
  );
  const value = runInNewContext(`(${source.slice(crm.start, crm.end)})`, {
    t: key => key,
    accountScopedRoute: name => ({ name }),
    hasJrcCrm: { value: true },
    hasCrmUserAccess: { value: true },
  });
  expect(value.children).toBeUndefined();
  expect(value.to.name).toBe('crm_dashboard');
  expect(value.activeOn).toContain('crm_order_new');
  expect(value.activeOn).toContain('crm_contract_new');
});
