// Browser Axios uses the isolated Vite /api proxy. Direct API probes use Rails
// port 5387; those responses are not browser clicks and must never be counted.
export const endingActivationURL = accountId => {
  const value = String(accountId);
  if (
    !['string', 'number'].includes(typeof accountId) ||
    !/^[1-9][0-9]*$/.test(value) ||
    !Number.isSafeInteger(Number(value))
  ) {
    throw new TypeError('Invalid synthetic browser account identity');
  }
  return `http://127.0.0.1:5386/api/v1/accounts/${value}/jrc_contact_center/acw_policy/ending_rules/activate`;
};

export const isEndingActivationRequest = (request, accountId) =>
  request.method() === 'POST' &&
  request.url() === endingActivationURL(accountId);
