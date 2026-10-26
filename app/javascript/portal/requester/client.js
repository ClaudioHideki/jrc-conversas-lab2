const csrf = () =>
  document.querySelector('meta[name="csrf-token"]')?.content || '';

export class PortalError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

export async function request(
  path,
  { body, method = 'GET', headers = {}, blob = false } = {}
) {
  const multipart = body instanceof FormData;
  const response = await fetch(path, {
    method,
    credentials: 'same-origin',
    cache: 'no-store',
    headers: {
      Accept: 'application/json',
      'X-CSRF-Token': csrf(),
      ...(!multipart && body ? { 'Content-Type': 'application/json' } : {}),
      ...headers,
    },
    ...(body ? { body: multipart ? body : JSON.stringify(body) } : {}),
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new PortalError(response.status, error.code || 'request_failed');
  }
  if (blob) return response.blob();
  if (response.status === 204) return {};
  return response.json();
}

export async function login(fields) {
  const response = await fetch('/auth/sign_in', {
    method: 'POST',
    credentials: 'same-origin',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf() },
    body: JSON.stringify(fields),
  });
  const payload = await response.json();
  if (payload.mfa_required || payload.sessions_limit_reached) return payload;
  if (!response.ok) throw new PortalError(response.status, 'login_failed');
  const headers = Object.fromEntries(
    ['access-token', 'client', 'uid', 'expiry', 'token-type'].map(key => [
      key,
      response.headers.get(key),
    ])
  );
  // Native credentials live only in this request; the bridge sets an encrypted,
  // HttpOnly cookie. Portal code never writes auth to local/session storage.
  return request('/portal/session', { method: 'POST', headers });
}

export const errorKey = error => {
  if (error.code === 'changed_submission') return 'PORTAL.SUBMISSION_UNCERTAIN';
  if (error.code === 'master_profile_incomplete')
    return 'PORTAL.PROFILE_INCOMPLETE';
  if (error.code === 'attachment_scan_unavailable') return 'PORTAL.SCAN';
  if (error.status === 409) return 'PORTAL.CONFLICT';
  if ([401, 403].includes(error.status)) return 'PORTAL.DENIED';
  return 'PORTAL.ERROR';
};

export const upload = (fields, files) => {
  const body = new FormData();
  Object.entries(fields).forEach(([key, value]) =>
    body.append(key, typeof value === 'object' ? JSON.stringify(value) : value)
  );
  files.forEach(file => body.append('files[]', file));
  return body;
};

export function submission() {
  let current;
  return {
    key(fields, files) {
      const signature = JSON.stringify({
        fields,
        files: files.map(file => [file.name, file.size, file.lastModified]),
      });
      if (current && current.signature !== signature)
        throw new PortalError(409, 'changed_submission');
      current ||= { signature, key: crypto.randomUUID() };
      return current.key;
    },
    failed(error) {
      if (!current) return;
      const rejected = [400, 401, 403, 404, 422].includes(error.status);
      if (rejected && !current.uncertain) current = null;
      else current.uncertain = true;
    },
    reset() {
      current = null;
    },
  };
}
