import assert from 'node:assert/strict';
import { test } from 'node:test';
import { paginateCalendarDays } from '../app/javascript/dashboard/routes/dashboard/crm/utils/calendarPagination.js';

test('pages across a day boundary without losing, duplicating or reordering appointments', () => {
  const days = [
    { key: '2026-11-07', activities: Array.from({ length: 30 }, (_, id) => ({ id })) },
    { key: '2026-11-09', activities: Array.from({ length: 31 }, (_, id) => ({ id: id + 30 })) },
  ];
  const before = structuredClone(days);
  const pages = [1, 2, 3].map(page => paginateCalendarDays(days, page));
  assert.deepEqual(pages.map(page => page.days.flatMap(day => day.activities).length), [25, 25, 11]);
  assert.deepEqual(pages[1].days.map(day => [day.key, day.activities.length]), [['2026-11-07', 5], ['2026-11-09', 20]]);
  assert.deepEqual(pages.flatMap(page => page.days.flatMap(day => day.activities.map(activity => activity.id))), Array.from({ length: 61 }, (_, id) => id));
  assert.deepEqual(days, before);
  assert.deepEqual(pages.map(({ page, pages: totalPages, total }) => [page, totalPages, total]), [[1, 3, 61], [2, 3, 61], [3, 3, 61]]);
});

test('clamps an old page after a filtered or refreshed authorized result shrinks', () => {
  const days = [{ key: '2026-11-07', activities: [{ id: 42 }] }];
  const page = paginateCalendarDays(days, 3);
  assert.equal(page.page, 1);
  assert.equal(page.pages, 1);
  assert.equal(page.total, 1);
  assert.deepEqual(page.days, days);
});

test('returns no synthetic rows or empty headers for an empty authorized list', () => {
  const page = paginateCalendarDays([{ key: '2026-11-07', activities: [] }], 2);
  assert.deepEqual(page, { page: 1, pages: 1, total: 0, days: [] });
});

test('keeps the 25/26 appointment page boundary exact without adding a blank page', () => {
  const activities = Array.from({ length: 26 }, (_, id) => ({ id }));
  assert.equal(paginateCalendarDays([{ activities: activities.slice(0, 25) }], 1).pages, 1);
  const page = paginateCalendarDays([{ activities }], 2);
  assert.equal(page.pages, 2);
  assert.deepEqual(page.days[0].activities, [{ id: 25 }]);
});
