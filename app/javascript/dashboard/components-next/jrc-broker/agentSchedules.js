const WEEK = 7 * 24 * 60;
const clock = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
export const emptyWeek = () =>
  Object.fromEntries(Array.from({ length: 7 }, (_, day) => [String(day), []]));
const minutes = value => {
  const [hour, minute] = value.split(':').map(Number);
  return hour * 60 + minute;
};

const validWeek = days => {
  if (
    !days ||
    Array.isArray(days) ||
    Object.keys(days).sort().join(',') !== '0,1,2,3,4,5,6'
  )
    return false;
  const ranges = [];
  const valid = Object.entries(days).every(([day, periods]) => {
    if (!Array.isArray(periods) || periods.length > 4) return false;
    return periods.every(period => {
      if (
        !period ||
        Object.keys(period).sort().join(',') !== 'end,start' ||
        !clock.test(period.start) ||
        (!clock.test(period.end) && period.end !== '24:00') ||
        period.start === period.end
      )
        return false;
      const start = Number(day) * 1440 + minutes(period.start);
      const endClock = minutes(period.end);
      const end =
        Number(day) * 1440 +
        endClock +
        (endClock <= minutes(period.start) ? 1440 : 0);
      if (end > WEEK) ranges.push([start, WEEK], [0, end - WEEK]);
      else ranges.push([start, end]);
      return true;
    });
  });
  ranges.sort((a, b) => a[0] - b[0]);
  return (
    valid &&
    ranges.every(
      (range, index) => index === 0 || ranges[index - 1][1] <= range[0]
    )
  );
};

export const validAgentSchedules = schedules =>
  schedules !== null &&
  typeof schedules === 'object' &&
  !Array.isArray(schedules) &&
  Object.keys(schedules).length <= 1000 &&
  Object.entries(schedules).every(
    ([id, days]) => /^[1-9]\d*$/.test(id) && validWeek(days)
  );
