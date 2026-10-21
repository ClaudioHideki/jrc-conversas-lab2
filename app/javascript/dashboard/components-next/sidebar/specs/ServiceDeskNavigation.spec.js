import { runInNewContext } from 'node:vm';
import { babelParse } from '@vue/compiler-sfc';
import sidebarSource from '../Sidebar.vue?raw';
import { visibleSidebarSections } from '../temporaryVisibility';
import { universityLink } from '../university';

// Execute the actual section composer: regression for a granted item silently
// dropped between menuItems and the template's menuSections.
const source = sidebarSource.split('<script setup>')[1].split('</script>')[0];
const node = babelParse(source, { sourceType: 'module' }).program.body.find(
  statement => statement.declarations?.[0]?.id.name === 'menuSections'
);
const sections = (items, unified = false) =>
  // The public university link is covered separately; it is not an operational grant.
  runInNewContext(`${source.slice(node.start, node.end)}; menuSections.value`, {
    computed: callback => ({ value: callback() }),
    menuItems: { value: items },
    legacyMenuItems: { value: [] },
    useUnifiedAttendanceNavigation: { value: unified },
    visibleSidebarSections,
    universityLink,
    t: key => key,
  }).filter(section => section.name !== 'learning');

describe('Service Desk final sidebar sections', () => {
  it('keeps service desk grants in their authorized sections in unified mode', () => {
    const result = sections(
      [
        { name: 'JRC Cockpit' },
        { name: 'Inbox' },
        { name: 'JRC Call Center' },
        { name: 'JRC Service Desk' },
        { name: 'JRC Service Desk Structure' },
      ],
      true
    );
    expect(
      result
        .find(section => section.name === 'attendance')
        .items.map(item => item.name)
    ).toEqual(['JRC Call Center', 'Inbox', 'JRC Cockpit']);
    expect(
      result
        .find(section => section.name === 'operations')
        .items.map(item => item.name)
    ).toEqual(['JRC Service Desk']);
    expect(
      result
        .find(section => section.name === 'administration')
        .items.map(item => item.name)
    ).toEqual(['JRC Service Desk Structure']);
  });
  it('shows structural access without granting operational navigation', () => {
    const result = sections([{ name: 'JRC Service Desk Structure' }]);
    expect(result).toHaveLength(1);
    expect(result[0].name).toBe('administration');
    expect(result[0].items.map(item => item.name)).toEqual([
      'JRC Service Desk Structure',
    ]);
  });
  it('shows agent operation without structural authority', () => {
    const result = sections([{ name: 'JRC Service Desk' }]);
    expect(result[0].name).toBe('attendance');
    expect(result.flatMap(section => section.items)).toHaveLength(1);
  });
  it('keeps both explicit grants and creates neither grant by itself', () => {
    expect(sections([])).toEqual([]);
    expect(
      sections([
        { name: 'JRC Service Desk' },
        { name: 'JRC Service Desk Structure' },
      ]).flatMap(section => section.items)
    ).toHaveLength(2);
  });
});
