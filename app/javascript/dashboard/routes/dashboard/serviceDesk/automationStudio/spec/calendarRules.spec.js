import { describe, it, expect } from 'vitest';
import { validCalendar, validCalendarHours } from '../calendarRules';
import {
  calendarIntervalsError,
  formatCalendarIntervals,
  parseCalendarIntervals,
} from '../calendarIntervals';
const calendar = () => ({
  timezone: 'America/Sao_Paulo',
  conditions: {
    format: 'jrc-sd-snapshot-calendar-v1',
    weekly: Object.fromEntries(
      ['1', '2', '3', '4', '5', '6', '7'].map(day => [
        day,
        day === '1' ? [['09:00', '18:00']] : [],
      ])
    ),
    holidays: [],
    exceptions: {},
  },
});
describe('Explicit OLA/notification calendar input', () => {
  it.each([
    ['one period', '08:00-18:00', [['08:00', '18:00']]],
    [
      'semicolon',
      '08:00-12:00;13:00-18:00',
      [
        ['08:00', '12:00'],
        ['13:00', '18:00'],
      ],
    ],
    [
      'compatible comma',
      '08:00-12:00,13:00-18:00',
      [
        ['08:00', '12:00'],
        ['13:00', '18:00'],
      ],
    ],
    [
      'surrounding spaces',
      ' 08:00 - 12:00 ; 13:00 - 18:00 ',
      [
        ['08:00', '12:00'],
        ['13:00', '18:00'],
      ],
    ],
    ['closed day', '   ', []],
    ['native end-of-day boundary', '00:00-24:00', [['00:00', '24:00']]],
  ])('parses %s into exact native two-item pairs', (_, input, rows) => {
    expect(parseCalendarIntervals(input)).toEqual({
      valid: true,
      rows,
      error: null,
    });
    expect(rows.every(pair => pair.length === 2)).toBe(true);
    expect(formatCalendarIntervals(rows)).toBe(
      input.trim() ? rows.map(pair => pair.join('-')).join(';') : ''
    );
  });
  it.each([
    ['non-padded time', '8:00-18:00', 'interval_time'],
    ['invalid time', '08:60-18:00', 'interval_time'],
    ['equal boundaries', '08:00-08:00', 'interval_order'],
    ['reversed boundaries', '18:00-08:00', 'interval_order'],
    ['overlap', '08:00-13:00;12:00-18:00', 'interval_overlap'],
    ['unordered intervals', '13:00-18:00;08:00-12:00', 'interval_overlap'],
    ['missing period', '08:00-12:00;;13:00-18:00', 'interval_format'],
    ['extra boundary', '08:00-12:00-18:00', 'interval_format'],
  ])(
    'rejects %s without manufacturing a corrected native payload',
    (_, input, error) => {
      expect(parseCalendarIntervals(input)).toEqual({
        valid: false,
        rows: null,
        error,
      });
    }
  );
  it('formats JSON canonically and retains malformed legacy text for explicit repair', () => {
    const rows = [
      ['08:00', '12:00'],
      ['13:00', '18:00'],
    ];
    expect(formatCalendarIntervals(rows)).toBe('08:00-12:00;13:00-18:00');
    const malformed = [['08:00', '12:00;13:00', '18:00']];
    const original = JSON.stringify(malformed);
    expect(calendarIntervalsError(malformed)).toBe('interval_format');
    expect(formatCalendarIntervals(malformed)).toBe('08:00-12:00;13:00-18:00');
    expect(JSON.stringify(malformed)).toBe(original);
    expect(
      parseCalendarIntervals(formatCalendarIntervals(malformed)).rows
    ).toEqual(rows);
  });
  it('permits incomplete private drafts but rejects malformed typed periods', () => {
    expect(validCalendarHours({ timezone: '', conditions: {} })).toBe(true);
    const value = calendar();
    value.conditions.weekly['1'] = '08:00-12:00;unfinished';
    expect(validCalendarHours(value)).toBe(false);
    expect(validCalendar(value)).toBe(false);
  });
  it('uses identical parsing and validation for exception dates and weekly periods', () => {
    const value = calendar();
    const parsed = parseCalendarIntervals('08:00-12:00;13:00-18:00');
    value.conditions.weekly['1'] = parsed.rows;
    value.conditions.exceptions = {
      '2026-10-27': parsed.rows,
      '2026-10-28': [],
    };
    expect(validCalendar(value)).toBe(true);
    value.conditions.exceptions['2026-10-27'] = [
      ['08:00', '12:00;13:00', '18:00'],
    ];
    expect(validCalendarHours(value)).toBe(false);
    expect(validCalendar(value)).toBe(false);
  });
  it('accepts explicit working hours, holidays and closed/open exception dates', () => {
    const value = calendar();
    value.conditions.holidays = ['2026-12-25'];
    value.conditions.exceptions = {
      '2026-12-24': [['08:00', '12:00']],
      '2026-12-31': [],
    };
    expect(validCalendar(value)).toBe(true);
  });
  it.each(['No/SuchZone', '', null])('rejects invalid timezone %s', zone => {
    const value = calendar();
    value.timezone = zone;
    expect(validCalendar(value)).toBe(false);
  });
  it.each([
    {
      reason: 'overlap',
      rows: [
        ['09:00', '12:00'],
        ['11:00', '18:00'],
      ],
    },
    { reason: 'overnight', rows: [['18:00', '09:00']] },
    { reason: 'invalid boundary', rows: [['09:00', '25:00']] },
  ])('rejects $reason', ({ rows }) => {
    const value = calendar();
    value.conditions.weekly['1'] = rows;
    expect(validCalendar(value)).toBe(false);
  });
  it('rejects malformed exception input and impossible dates instead of retaining an old valid configuration', () => {
    const value = calendar();
    value.conditions.exceptions = 'invalid';
    expect(validCalendar(value)).toBe(false);
    value.conditions.exceptions = { '2026-02-30': [] };
    expect(validCalendar(value)).toBe(false);
  });
  it('does not invent business hours for an empty calendar', () => {
    const value = calendar();
    value.conditions.weekly['1'] = [];
    expect(validCalendar(value)).toBe(false);
  });
});
