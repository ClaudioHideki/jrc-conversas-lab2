import { login, request } from '../requester/client';

export const root = '/portal/manual-de-cultura';
export const session = () => request(`${root}/session`);
export const signIn = fields => login(fields, `${root}/session`);
export const apiRoot = accountId => `${root}/api/accounts/${accountId}`;
export { request };

export const formatDate = value =>
  value
    ? new Intl.DateTimeFormat('pt-BR', {
        dateStyle: 'short',
        timeStyle: 'short',
        timeZone: 'America/Sao_Paulo',
      }).format(new Date(value))
    : '—';

export function filterQuery(values) {
  return new URLSearchParams(
    Object.entries(values).filter(([, value]) => value !== '' && value != null)
  ).toString();
}

export function filePath(base, id, kind) {
  return `${base}/versions/${id}/files/${kind}`;
}
