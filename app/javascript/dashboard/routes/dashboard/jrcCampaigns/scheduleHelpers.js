import { formatInTimeZone, zonedTimeToUtc } from 'date-fns-tz';

export const defaultCampaignTimezone = accountTimezone =>
  accountTimezone || Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';

export const campaignWallTime = (instant, timezone) =>
  formatInTimeZone(new Date(instant), timezone, "yyyy-MM-dd'T'HH:mm");

export const campaignScheduledInstant = (wallTime, timezone) =>
  zonedTimeToUtc(wallTime, timezone).toISOString();

export const formatCampaignTime = (instant, timezone = 'UTC') =>
  instant
    ? formatInTimeZone(new Date(instant), timezone, 'dd/MM/yyyy HH:mm')
    : '';

// Preview only; the reviewed backend estimate and persisted jobs remain authoritative.
export const campaignWindowEstimate = (window, base) => {
  const clock = /^(?:[01]\d|2[0-3]):[0-5]\d$/;
  if (
    !clock.test(window.start) ||
    !clock.test(window.end) ||
    window.start >= window.end
  )
    return null;
  const timezone = window.timezone || 'UTC';
  const date = formatInTimeZone(base, timezone, 'yyyy-MM-dd');
  const midnight = new Date(`${date}T00:00:00Z`);
  for (let offset = 0; offset < 14; offset += 1) {
    const day = new Date(midnight.getTime() + offset * 86400000);
    if (window.days?.map(Number).includes(day.getUTCDay())) {
      const localDate = day.toISOString().slice(0, 10);
      const start = zonedTimeToUtc(`${localDate}T${window.start}:00`, timezone);
      const end = zonedTimeToUtc(`${localDate}T${window.end}:00`, timezone);
      if (base <= end)
        return new Date(Math.max(base.getTime(), start.getTime()));
    }
  }
  return null;
};
