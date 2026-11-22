// Browser Axios uses the owned preview origin; APIRequestContext uses the separate Rails origin.
export const isBrowserApiResponse = (response, browserUrl, apiUrl, method) => {
  const api = new URL(apiUrl);
  const expected = new URL(
    api.pathname + api.search,
    new URL(browserUrl).origin
  );
  return (
    response.url() === expected.href && response.request().method() === method
  );
};
