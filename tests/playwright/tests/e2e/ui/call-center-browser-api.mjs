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

// Bind the actual owned tab, which may differ from an untouched about:blank parent fixture.
export const bindBrowserApiResponse =
  (page, apiOrigin) => (response, path, method) =>
    isBrowserApiResponse(
      response,
      page.url(),
      new URL(path, apiOrigin).href,
      method
    );
