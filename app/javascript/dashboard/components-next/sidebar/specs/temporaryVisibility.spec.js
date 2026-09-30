import { visibleSidebarSections } from '../temporaryVisibility';

describe('temporary sidebar presentation', () => {
  it('hides only the three legacy entries without changing other modules or routes', () => {
    const calls = {
      name: 'JRC Calls Center',
      label: 'Ligações',
      children: [
        { name: 'Webphone', label: 'Ramal JRC', to: { name: 'ramal_index' } },
        { name: 'Call History', label: 'Histórico de ligações' },
      ],
    };
    const retained = [
      calls,
      ...[
        'CRM',
        'JRC Campaigns',
        'JRC Service Desk',
        'JRC Projects',
        'JRC Agenda',
        'Contacts',
        'Settings',
      ].map(name => ({ name })),
    ];
    const legacy = ['Calls', 'Campaigns', 'Portals'].map(name => ({
      name,
      to: { name: `${name}-route` },
    }));
    const sections = [
      { name: 'main', items: [...retained, ...legacy] },
      { name: 'legacy-tools', items: legacy },
      { name: 'empty', items: [] },
    ];
    const before = JSON.stringify(sections);
    const result = visibleSidebarSections(sections);
    expect(result.map(section => section.name)).toEqual(['main']);
    expect(result[0].items).toEqual(retained);
    expect(result[0].items[0]).toBe(calls);
    expect(result[0].items[0].children[0].label).toBe('Ramal JRC');
    expect(JSON.stringify(sections)).toBe(before);
  });

  it.each(['administrator', 'agent'])(
    'applies equally to %s in any account without consulting permissions',
    role => {
      [1, 2, 999].forEach(accountId => {
        const items = ['Calls', 'Campaigns', 'Portals', 'JRC Calls Center'].map(
          name => ({ name, role, accountId })
        );
        expect(visibleSidebarSections([{ items }])[0].items).toEqual([
          items[3],
        ]);
      });
    }
  );
});
