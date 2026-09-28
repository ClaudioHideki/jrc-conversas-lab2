import { filterActivities } from './activityFilters';

const records = [
  {
    id: 1,
    title: 'Retorno',
    lead: { name: 'Maria' },
    activity_type: 'call',
    user: { id: 2 },
    overdue: true,
    status: 'scheduled',
  },
  {
    id: 2,
    title: 'Visita',
    deal: { title: 'Contrato JRC' },
    activity_type: 'meeting',
    user: { id: 3 },
    completed_at: '2026-09-25',
    overdue: true,
  },
  {
    id: 3,
    title: 'Cancelada',
    activity_type: 'call',
    status: 'cancelled',
    overdue: true,
  },
];
const empty = { search: '', type: '', owner: '', status: '' };
describe('CRM activity filters', () => {
  it('combines search, type, responsible and status without modifying API records', () => {
    const snapshot = JSON.stringify(records);
    expect(
      filterActivities(records, {
        search: ' MARIA ',
        type: 'call',
        owner: '2',
        status: 'overdue',
      }).map(x => x.id)
    ).toEqual([1]);
    expect(JSON.stringify(records)).toBe(snapshot);
  });
  it('matches related deal names and clears all filters', () => {
    expect(
      filterActivities(records, { ...empty, search: 'jrc' }).map(x => x.id)
    ).toEqual([2]);
    expect(filterActivities(records, empty)).toEqual(records);
  });
  it('does not count canceled or completed records as open/overdue', () => {
    expect(
      filterActivities(records, { ...empty, status: 'overdue' }).map(x => x.id)
    ).toEqual([1]);
    expect(
      filterActivities(records, { ...empty, status: 'open' }).map(x => x.id)
    ).toEqual([1]);
    expect(
      filterActivities(records, { ...empty, status: 'completed' }).map(
        x => x.id
      )
    ).toEqual([2]);
  });
});
