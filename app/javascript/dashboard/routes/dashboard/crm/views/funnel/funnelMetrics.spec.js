import { funnelMetrics, funnelTotals } from './funnelMetrics';

const stages = [1, 2, 3, 4].map(id => ({
  id,
  active: true,
  name: String(id),
  is_won: id === 3,
  is_lost: id === 4,
}));
const date = day => `2026-11-${String(day).padStart(2, '0')}T12:00:00Z`;
const movement = (from, to, day) => ({ from, to, at: date(day) });
const won = {
  id: 1,
  created_at: date(1),
  won_at: date(6),
  updated_at: date(6),
  stage_id: 3,
  status: 'won',
  value_cents: 18000,
  currency: 'BRL',
  moves: [movement(1, 2, 3), movement(2, 3, 6)],
};
const open = {
  id: 2,
  created_at: date(1),
  updated_at: date(8),
  stage_id: 2,
  status: 'open',
  value_cents: 17000,
  currency: 'USD',
  moves: [],
  next_activity: false,
};
const replayed = {
  id: 3,
  created_at: date(1),
  updated_at: date(9),
  stage_id: 2,
  status: 'open',
  value_cents: 19000,
  currency: 'BRL',
  moves: [movement(null, 2, 3), movement(2, 1, 4), movement(1, 2, 9)],
};
const report = { as_of: date(28), stages, deals: [won, open, replayed] };

it('keeps cohort bars, histories, advancement and drill-down durations consistent', () => {
  const metrics = funnelMetrics(report, 'conversion');
  const [first, next] = metrics.stages;
  expect(metrics.entry.rows).toHaveLength(3);
  expect(metrics.conversion).toBeCloseTo(100 / 3);
  expect(metrics.averageCycle).toBe(5);
  expect(first.rows.map(item => item.deal.id)).toEqual([1, 3]);
  expect(first.rows[0].enteredAt).toBeNull();
  expect(metrics.advancement['1']).toBe(100);
  expect(next.measured.map(item => [item.deal.id, item.days])).toEqual([
    [1, 3],
    [3, 1],
  ]);
  expect(next.averageDays).toBe(2);
  expect(funnelTotals(next.rows)).toEqual([
    ['BRL', 37000],
    ['USD', 17000],
  ]);
});

it('uses current stages and known entry dates for the open portfolio', () => {
  const metrics = funnelMetrics(
    { ...report, deals: [open, replayed] },
    'portfolio'
  );
  expect(metrics.stages[0].rows).toEqual([]);
  expect(metrics.stages[1].rows.map(item => item.deal.id)).toEqual([2, 3]);
  expect(metrics.stages[1].measured.map(item => item.deal.id)).toEqual([3]);
  expect(metrics.stalled.map(item => item.deal.id)).toEqual([2, 3]);
  expect(metrics.advancement).toEqual({});
});
