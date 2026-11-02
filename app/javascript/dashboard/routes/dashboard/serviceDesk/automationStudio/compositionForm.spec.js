import {
  blankComposition,
  clone,
  compositionPayload,
  emptyCalendar,
  snapshotFor,
  publicationMatches,
  stable,
  validCompositionCalendars,
  validCompositionCalendarHours,
} from './compositionForm';
import { parseCalendarIntervals } from './calendarIntervals';
describe('Native automation composition transport', () => {
  it.each(['08:00-12:00;13:00-18:00', '08:00-12:00,13:00-18:00'])(
    'keeps schema 2 and exactly three SLA clock budgets with calendar input %s',
    input => {
      const value = blankComposition('lifecycle');
      value.code = 'explicit-sla';
      value.definition.lifecycle.sla.mode = 'calendar_snapshot';
      const budgets = {
        first_response: 30 * 60,
        attendance: 60 * 60,
        resolution: 240 * 60,
      };
      value.definition.families.sla_selection = {
        rules: [
          {
            key: 'normal',
            precedence: 1,
            match: { priority_id: 8 },
            output: {
              snapshot: {
                policy_conditions: { clock_budgets_seconds: budgets },
              },
            },
          },
        ],
      };
      const calendar = emptyCalendar();
      calendar.timezone = 'America/Sao_Paulo';
      calendar.conditions.weekly['1'] = parseCalendarIntervals(input).rows;
      const previous = stable(value);
      const result = compositionPayload(
        value,
        0,
        calendar,
        'explicit-calendar',
        'v1'
      );
      expect(result.definition.lifecycle.schema_version).toBe(2);
      expect(
        result.definition.families.sla_selection.rules[0].output.snapshot
          .calendar_conditions.weekly['1']
      ).toEqual([
        ['08:00', '12:00'],
        ['13:00', '18:00'],
      ]);
      expect(
        result.definition.families.sla_selection.rules[0].output.snapshot
          .policy_conditions.clock_budgets_seconds
      ).toEqual({ first_response: 1800, attendance: 3600, resolution: 14400 });
      expect(
        Object.keys(
          result.definition.families.sla_selection.rules[0].output.snapshot
            .policy_conditions.clock_budgets_seconds
        )
      ).toEqual(['first_response', 'attendance', 'resolution']);
      expect(validCompositionCalendars(value, calendar)).toBe(true);
      expect(stable(value)).toBe(previous);
    }
  );
  it('validates only selected calendars and rejects malformed periods in SLA, OLA, routing and notification windows', () => {
    const value = blankComposition('operational');
    const calendar = emptyCalendar();
    expect(validCompositionCalendars(value, calendar)).toBe(true);
    calendar.timezone = 'America/Sao_Paulo';
    calendar.conditions.weekly['1'] = [['08:00', '12:00;13:00', '18:00']];
    value.definition.families.routing.rules[0].window = calendar;
    expect(validCompositionCalendars(value, emptyCalendar())).toBe(false);
    expect(validCompositionCalendarHours(value, emptyCalendar())).toBe(false);
    calendar.conditions.weekly['1'] = parseCalendarIntervals(
      '08:00-12:00;13:00-18:00'
    ).rows;
    expect(validCompositionCalendars(value, emptyCalendar())).toBe(true);
    delete value.definition.families.routing.rules[0].window;
    value.definition.queues.push({
      id: 7,
      attributes: { ola_time_basis: 'business', ola_calendar: calendar },
    });
    expect(validCompositionCalendars(value, emptyCalendar())).toBe(true);
    value.definition.notifications.push({
      settings: { window: { ...calendar, enabled: true } },
    });
    calendar.conditions.weekly['1'] = 'invalid';
    expect(validCompositionCalendars(value, emptyCalendar())).toBe(false);
  });
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
