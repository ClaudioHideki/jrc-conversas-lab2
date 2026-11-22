import assert from 'node:assert/strict';
import test from 'node:test';
import { isBrowserApiResponse } from './call-center-browser-api.mjs';

const browser =
  'http://127.0.0.1:5386/app/accounts/91/contact-center/control-desk/hours?calendar_unit=22';
const api =
  'http://127.0.0.1:5387/api/v1/accounts/91/jrc_contact_center/queue_calendars/33';
const response = (url, method = 'PATCH') => ({
  url: () => url,
  request: () => ({ method: () => method }),
});
const proxied =
  'http://127.0.0.1:5386/api/v1/accounts/91/jrc_contact_center/queue_calendars/33';

test('matches the actual browser mutation through its own preview origin', () => {
  assert.equal(
    isBrowserApiResponse(response(proxied), browser, api, 'PATCH'),
    true
  );
});
test('reproduces the previous impossible comparison with the direct Rails URL', () => {
  assert.notEqual(proxied, api);
  assert.equal(
    isBrowserApiResponse(response(api), browser, api, 'PATCH'),
    false
  );
});
test('rejects a response from a different preview or a foreign origin', () => {
  assert.equal(
    isBrowserApiResponse(
      response(proxied.replace(':5386', ':5385')),
      browser,
      api,
      'PATCH'
    ),
    false
  );
  assert.equal(
    isBrowserApiResponse(
      response(proxied.replace('127.0.0.1', 'example.invalid')),
      browser,
      api,
      'PATCH'
    ),
    false
  );
});
test('rejects a different account despite the same endpoint and method', () => {
  assert.equal(
    isBrowserApiResponse(
      response(proxied.replace('accounts/91', 'accounts/92')),
      browser,
      api,
      'PATCH'
    ),
    false
  );
});
test('rejects a different native queue', () => {
  assert.equal(
    isBrowserApiResponse(
      response(proxied.replace('/33', '/34')),
      browser,
      api,
      'PATCH'
    ),
    false
  );
});
test('does not confuse reads or other writes with the exact expected mutation', () => {
  for (const method of ['GET', 'POST', 'DELETE']) {
    assert.equal(
      isBrowserApiResponse(response(proxied, method), browser, api, 'PATCH'),
      false
    );
  }
});
test('preserves an exact endpoint query and rejects a missing or different query', () => {
  assert.equal(
    isBrowserApiResponse(
      response(proxied + '?unit_id=22'),
      browser,
      api + '?unit_id=22',
      'PATCH'
    ),
    true
  );
  assert.equal(
    isBrowserApiResponse(
      response(proxied),
      browser,
      api + '?unit_id=22',
      'PATCH'
    ),
    false
  );
  assert.equal(
    isBrowserApiResponse(
      response(proxied + '?unit_id=23'),
      browser,
      api + '?unit_id=22',
      'PATCH'
    ),
    false
  );
});
test('uses the owned browser scheme without retaining its page path or query', () => {
  assert.equal(
    isBrowserApiResponse(
      response(proxied.replace('http:', 'https:')),
      browser.replace('http:', 'https:'),
      api,
      'PATCH'
    ),
    true
  );
});
test('does not loosen response status checks, which remain the responsibility of the caller', () => {
  const found = response(proxied);
  found.status = () => 409;
  assert.equal(isBrowserApiResponse(found, browser, api, 'PATCH'), true);
  assert.equal(found.status(), 409);
});
