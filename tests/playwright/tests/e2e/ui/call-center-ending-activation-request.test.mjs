import test from 'node:test';
import assert from 'node:assert/strict';
import {
  endingActivationURL,
  isEndingActivationRequest,
} from './call-center-ending-activation-request.mjs';

const browser = endingActivationURL('1');
const request = (url = browser, method = 'POST') => ({
  url: () => url,
  method: () => method,
});

test('matches the exact browser proxy activation request', () => {
  assert.equal(isEndingActivationRequest(request(), '1'), true);
});

test('reproduces why the former Rails-origin observer missed a real browser POST', () => {
  const oldExpected = browser.replace(':5386/', ':5387/');
  assert.notEqual(request().url(), oldExpected);
  assert.equal(isEndingActivationRequest(request(), '1'), true);
});

test('does not count a direct Rails API probe as a browser click', () => {
  assert.equal(
    isEndingActivationRequest(
      request(browser.replace(':5386/', ':5387/')),
      '1'
    ),
    false
  );
});

test('rejects another account while retaining the complete endpoint identity', () => {
  assert.equal(
    isEndingActivationRequest(request(endingActivationURL('2')), '1'),
    false
  );
});

test('rejects reads and other methods', () => {
  for (const method of ['GET', 'HEAD', 'PATCH', 'DELETE']) {
    assert.equal(
      isEndingActivationRequest(request(browser, method), '1'),
      false
    );
  }
});

test('rejects similar paths, query strings, fragments, trailing slash and foreign origins', () => {
  for (const url of [
    browser + '_other',
    browser + '?review=1',
    browser + '#receipt',
    browser + '/',
    browser.replace('127.0.0.1', 'localhost'),
    browser.replace('http:', 'https:'),
  ]) {
    assert.equal(isEndingActivationRequest(request(url), '1'), false);
  }
});

test('rejects malformed account identities rather than broadening URL matching', () => {
  for (const value of [
    0,
    -1,
    '',
    '01',
    '1/2',
    '1?scope=2',
    null,
    [1],
    {},
    '9007199254740992',
  ]) {
    assert.throws(() => endingActivationURL(value), TypeError);
  }
});

test('retains exact account identity for both native string and safe integer input', () => {
  assert.equal(endingActivationURL(1), browser);
  assert.equal(isEndingActivationRequest(request(), 1), true);
});
