import { validMembershipCapacity } from './portfolioMembershipCapacityReceipt';
const value = {
  read_only: true,
  captured_at: '2026-11-06T12:00:00Z',
  state: 'projected',
  rows: [
    {
      scope_key: 'portfolio:18',
      user_id: 7,
      configuration_version: 1,
      unit: 'hours',
      blocker: null,
      current: 2,
      incoming: 4,
      projected: 6,
      effective_capacity: 5,
      available_after: -1,
    },
  ],
};
it('accepts existing immutable reviews without inventing new captured capacity', () => {
  expect(validMembershipCapacity(undefined, 18)).toBe(true);
  expect(validMembershipCapacity(value, 18)).toBe(true);
});
it('requires missing weights to remain unavailable instead of accepting fabricated zero facts', () => {
  const identity = {
    scope_key: 'portfolio:18',
    user_id: 7,
    configuration_version: 1,
    unit: 'hours',
    blocker: 'capacity_workload_missing',
  };
  expect(validMembershipCapacity({ ...value, rows: [identity] }, 18)).toBe(
    true
  );
  expect(
    validMembershipCapacity(
      {
        ...value,
        rows: [{ ...identity, current: 0, incoming: 0, projected: 0 }],
      },
      18
    )
  ).toBe(false);
});
it('rejects foreign group metadata, unknown units and invalid numeric facts', () => {
  expect(validMembershipCapacity(value, 19)).toBe(false);
  expect(
    validMembershipCapacity(
      { ...value, rows: [{ ...value.rows[0], unit: 'invented' }] },
      18
    )
  ).toBe(false);
  expect(
    validMembershipCapacity(
      { ...value, rows: [{ ...value.rows[0], projected: Infinity }] },
      18
    )
  ).toBe(false);
});
it('keeps denied or unconfigured states free of any workload rows', () => {
  expect(
    validMembershipCapacity({ ...value, state: 'scope_denied', rows: [] }, 18)
  ).toBe(true);
  expect(
    validMembershipCapacity({ ...value, state: 'not_configured' }, 18)
  ).toBe(false);
  expect(
    validMembershipCapacity(
      { ...value, state: 'controlled_review_required', rows: [] },
      18
    )
  ).toBe(true);
});
