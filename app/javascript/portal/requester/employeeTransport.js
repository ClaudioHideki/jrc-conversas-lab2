import { request } from './client';

// Native API contracts, with the existing Portal's HttpOnly authentication and CSRF.
export function employeeTransport(accountId) {
  const prefix = `/api/v1/accounts/${accountId}/jrc_service_desk`;
  const invoke = async (url, body, options = {}, method = 'GET') => {
    if (!url.startsWith(`${prefix}/`))
      throw new TypeError('Foreign employee context');
    const path = url.replace(prefix, `/portal/employee/accounts/${accountId}`);
    const query = new URLSearchParams(options.params || {});
    try {
      const data = await request(`${path}${query.size ? `?${query}` : ''}`, {
        method,
        body,
        headers: options.headers || {},
        signal: options.signal,
      });
      return { data };
    } catch (error) {
      throw Object.assign(error, {
        response: { status: error.status, data: { code: error.code } },
      });
    }
  };
  return {
    get: (url, options) => invoke(url, undefined, options),
    post: (url, body, options) => invoke(url, body, options, 'POST'),
    patch: (url, body, options) => invoke(url, body, options, 'PATCH'),
  };
}
