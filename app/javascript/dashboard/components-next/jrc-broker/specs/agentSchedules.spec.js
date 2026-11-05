import { emptyWeek, validAgentSchedules } from '../agentSchedules';

it('accepts lunch breaks, touching periods and a full day', () => {
  const week = emptyWeek();
  week[1] = [
    { start: '09:00', end: '12:00' },
    { start: '13:00', end: '18:00' },
  ];
  week[2] = [
    { start: '00:00', end: '12:00' },
    { start: '12:00', end: '24:00' },
  ];
  expect(validAgentSchedules({ 1: week })).toBe(true);
});

it('rejects overlaps across midnight at the weekly boundary', () => {
  const week = emptyWeek();
  week[6] = [{ start: '22:00', end: '06:00' }];
  week[0] = [{ start: '05:00', end: '08:00' }];
  expect(validAgentSchedules({ 1: week })).toBe(false);
  week[0] = [{ start: '06:00', end: '08:00' }];
  expect(validAgentSchedules({ 1: week })).toBe(true);
});

it('rejects incomplete, malformed and zero-length shifts', () => {
  expect(validAgentSchedules({ 1: {} })).toBe(false);
  expect(validAgentSchedules({ '01': emptyWeek() })).toBe(false);
  expect(validAgentSchedules({ 1: Object.values(emptyWeek()) })).toBe(false);
  const week = emptyWeek();
  week[1] = [{ start: '09:00', end: '09:00' }];
  expect(validAgentSchedules({ 1: week })).toBe(false);
});
