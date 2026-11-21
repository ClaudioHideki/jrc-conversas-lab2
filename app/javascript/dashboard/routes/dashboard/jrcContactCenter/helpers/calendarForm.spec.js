import { describe, expect, it } from 'vitest';
import {
  calendarSchedule,
  newCalendarDefinition,
  updateCalendarSchedule,
  validCalendarDefinition,
} from './calendarForm';

const definition = () => ({
  ...newCalendarDefinition('America/Sao_Paulo'),
  name: 'SYNTHETIC unit hours',
  weekly: Object.fromEntries(
    [1, 2, 3, 4, 5, 6, 7].map(day => [
      String(day),
      day <= 5
        ? [
            ['08:00', '12:00'],
            ['13:00', '17:00'],
          ]
        : [],
    ])
  ),
  holidays: [
    {
      date: '2026-11-23',
      name: 'SYNTHETIC explicit holiday',
      kind: 'internal',
      type: 'movable',
    },
  ],
  exceptions: [
    {
      date: '2026-11-23',
      name: 'SYNTHETIC duty',
      intervals: [['10:00', '11:00']],
    },
  ],
});

describe('Call Center metadata adapter to the existing native calendar form contract', () => {
  it('starts without invented working hours, locality, name, holiday formula or timezone fallback', () => {
    const draft = newCalendarDefinition('America/Sao_Paulo');
    expect(draft.weekly).toEqual(
      Object.fromEntries([1, 2, 3, 4, 5, 6, 7].map(day => [String(day), []]))
    );
    expect(draft).toMatchObject({
      name: '',
      timezone: 'America/Sao_Paulo',
      holidays: [],
      exceptions: [],
    });
    expect(validCalendarDefinition(draft)).toBe(false);
    expect(newCalendarDefinition('').timezone).toBe('');
  });

  it('retains every explicit interval and the native contract without fabricating a published state', () => {
    const value = definition();
    expect(validCalendarDefinition(value)).toBe(true);
    expect(calendarSchedule(value)).toEqual({
      timezone: value.timezone,
      conditions: {
        format: 'jrc-sd-snapshot-calendar-v1',
        weekly: value.weekly,
        holidays: ['2026-11-23'],
        exceptions: { '2026-11-23': [['10:00', '11:00']] },
      },
    });
    const projected = calendarSchedule(value);
    projected.conditions.weekly['1'].splice(0);
    expect(value.weekly['1']).toHaveLength(2);
    expect(projected).not.toHaveProperty('published');
  });

  it('preserves explicit holiday metadata while new dates remain incomplete until the user fills them', () => {
    const value = definition();
    const schedule = calendarSchedule(value);
    schedule.conditions.holidays.push('2026-12-01');
    const result = updateCalendarSchedule(value, schedule);
    expect(result.holidays[0]).toEqual(value.holidays[0]);
    expect(result.holidays[1]).toEqual({
      date: '2026-12-01',
      name: '',
      kind: '',
      type: '',
    });
    expect(validCalendarDefinition(result)).toBe(false);
    expect(value.holidays).toHaveLength(1);
  });

  it('keeps malformed exception text visible and invalid instead of silently restoring old valid hours', () => {
    const value = definition();
    const schedule = calendarSchedule(value);
    schedule.conditions.exceptions['2026-11-23'] = '08:00-12:00;invalid';
    const result = updateCalendarSchedule(value, schedule);
    expect(result.exceptions[0]).toEqual({
      ...value.exceptions[0],
      intervals: '08:00-12:00;invalid',
    });
    expect(validCalendarDefinition(result)).toBe(false);
    expect(value.exceptions[0].intervals).toEqual([['10:00', '11:00']]);
  });

  it('preserves an explicitly closed exception over a holiday without requiring fake working hours for that date', () => {
    const value = definition();
    const schedule = calendarSchedule(value);
    schedule.conditions.exceptions['2026-11-23'] = [];
    const result = updateCalendarSchedule(value, schedule);
    expect(validCalendarDefinition(result)).toBe(true);
    expect(
      calendarSchedule(result).conditions.exceptions['2026-11-23']
    ).toEqual([]);
  });

  const invalid = {
    'blank timezone': value => {
      value.timezone = '';
    },
    'unknown timezone': value => {
      value.timezone = 'SYNTHETIC/Unknown';
    },
    'overlapping regular intervals': value => {
      value.weekly['1'] = [
        ['08:00', '12:00'],
        ['11:00', '17:00'],
      ];
    },
    'overlapping exception intervals': value => {
      value.exceptions[0].intervals = [
        ['08:00', '12:00'],
        ['11:00', '17:00'],
      ];
    },
    'missing explicit weekday': value => {
      delete value.weekly['7'];
    },
    'duplicate exception dates': value => {
      value.exceptions.push(structuredClone(value.exceptions[0]));
    },
    'duplicate holiday dates': value => {
      value.holidays.push(structuredClone(value.holidays[0]));
    },
    'an impossible date': value => {
      value.holidays[0].date = '2026-02-30';
    },
    'an unnamed holiday': value => {
      value.holidays[0].name = '';
    },
    'an unknown locality classification': value => {
      value.holidays[0].kind = 'provider_default';
    },
    'an invented formula': value => {
      value.holidays[0].type = 'easter_plus_unknown';
    },
    'false holiday entries': value => {
      value.holidays = [false];
    },
    'false exception entries': value => {
      value.exceptions = [false];
    },
    'a caller supplied authority field': value => {
      value.account_id = '999';
    },
  };
  Object.entries(invalid).forEach(([name, change]) => {
    it(`rejects ${name} before enabling the internal save button`, () => {
      const value = definition();
      change(value);
      expect(validCalendarDefinition(value)).toBe(false);
    });
  });
});
