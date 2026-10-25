import { describe, it, expect } from 'vitest';
import { validCalendar } from '../calendarRules';
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
