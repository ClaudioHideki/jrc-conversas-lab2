import { runInNewContext } from 'node:vm';
import { babelParse } from '@vue/compiler-sfc';
import sidebarSource from '../Sidebar.vue?raw';

// Execute the actual section composer: regression for a granted item silently
// dropped between menuItems and the template's menuSections.
const source = sidebarSource.split('<script setup>')[1].split('</script>')[0];
const node = babelParse(source, { sourceType: 'module' }).program.body.find(
  statement => statement.declarations?.[0]?.id.name === 'menuSections'
);
const sections = items =>
  runInNewContext(`${source.slice(node.start, node.end)}; menuSections.value`, {
    computed: callback => ({ value: callback() }),
    menuItems: { value: items },
    legacyMenuItems: { value: [] },
  });

describe('Service Desk final sidebar sections', () => {
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
