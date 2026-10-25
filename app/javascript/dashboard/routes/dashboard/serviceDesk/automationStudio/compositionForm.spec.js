import {
  blankComposition,
  clone,
  compositionPayload,
  emptyCalendar,
  snapshotFor,
  publicationMatches,
  stable,
} from './compositionForm';
describe('Native automation composition transport', () => {
  it('keeps new compositions disabled and uses explicit empty configurations', () => {
    const value = blankComposition('lifecycle');
    expect(value.enabled).toBe(false);
    expect(value.definition.lifecycle.transitions).toEqual([]);
    expect(value.definition.queues).toEqual([]);
    expect(value.definition.notifications).toEqual([]);
    expect(emptyCalendar().timezone).toBe('');
    expect(Object.values(emptyCalendar().conditions.weekly)).toEqual([
      [],
      [],
      [],
      [],
      [],
      [],
      [],
    ]);
  });
  it('preserves explicit rule service scopes and does not mutate the private draft', () => {
    const value = blankComposition('operational');
    value.definition.families.routing.rules[0].match.service_id = 91;
    const original = stable(value);
    const result = compositionPayload(value, 0, emptyCalendar(), '', '');
    expect(result.definition.families.routing.rules[0].match.service_id).toBe(
      91
    );
    expect(stable(value)).toBe(original);
  });
  it('binds the selected service across native families and stamps explicit snapshot provenance', () => {
    const value = blankComposition('lifecycle');
    Object.assign(value, { code: 'synthetic-policy', service_id: 91 });
    value.definition.families.sla_selection = {
      rules: [
        {
          key: 'priority',
          precedence: 2,
          match: { priority_id: 8 },
          output: {
            snapshot: {
              policy_conditions: {
                clock_budgets_seconds: {
                  first_response: 600,
                  attendance: 300,
                  resolution: 3600,
                },
              },
            },
          },
        },
      ],
    };
    const calendar = emptyCalendar();
    calendar.timezone = 'America/Sao_Paulo';
    const output = compositionPayload(
      value,
      4,
      calendar,
      'explicit-calendar',
      'v3'
    );
    expect(output.definition.families.sla_selection.rules[0].match).toEqual({
      service_id: 91,
      priority_id: 8,
    });
    expect(
      output.definition.families.sla_selection.rules[0].output.snapshot
    ).toEqual(
      snapshotFor(value, 4, calendar, 'explicit-calendar', 'v3', {
        first_response: 600,
        attendance: 300,
        resolution: 3600,
      })
    );
  });
  it('requires readback to match the exact version, definition, activation, scope and digest format', () => {
    const value = blankComposition('operational');
    const row = { ...clone(value), version: 2, digest: 'a'.repeat(64) };
    expect(publicationMatches(row, value, 1)).toBe(true);
    [
      { version: 3 },
      { service_id: 7 },
      { enabled: true },
      { definition: {} },
      { digest: 'unknown' },
    ].forEach(patch => {
      expect(publicationMatches({ ...row, ...patch }, value, 1)).toBe(false);
    });
  });
});
