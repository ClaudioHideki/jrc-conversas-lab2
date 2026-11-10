import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { parseCalendarDate } from '../app/javascript/dashboard/routes/dashboard/crm/utils/calendarDate.js';
const helper = pathToFileURL(path.resolve(import.meta.dirname, '../app/javascript/dashboard/routes/dashboard/crm/utils/calendarDate.js')).href;
for (const zone of ['America/Sao_Paulo', 'UTC', 'America/Los_Angeles', 'Asia/Tokyo']) {
  test(`date-only navigation keeps its selected calendar day in ${zone}`, () => {
    const script = `import {parseCalendarDate} from ${JSON.stringify(helper)}; const d=parseCalendarDate('2026-11-07'); console.log(JSON.stringify([d.getFullYear(),d.getMonth()+1,d.getDate(),d.getHours()]));`;
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', script], { env: { ...process.env, TZ: zone }, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), [2026,11,7,0]);
  });
}
for (const value of ['', 'not-a-date', '2026-02-29', '2026-04-31', '2026-13-01', '2026-00-10', '2026-01-00', null, false, [], {}]) {
  test(`invalid date input is rejected: ${JSON.stringify(value)}`, () => assert.equal(parseCalendarDate(value), null));
}
test('leap-day date is accepted and not normalized to March', () => {
  const d = parseCalendarDate('2028-02-29'); assert.equal(d.getMonth(), 1); assert.equal(d.getDate(), 29);
});
test('ISO instant with explicit zone retains its existing absolute meaning', () => {
  const value='2026-11-07T03:00:00Z'; assert.equal(parseCalendarDate(value).getTime(),new Date(value).getTime());
});
test('years below 100 are not coerced to the twentieth century', () => {
  assert.equal(parseCalendarDate('0099-06-05').getFullYear(),99);
});
