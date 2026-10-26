/* global globalThis */
export function operationKey() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  const bytes = new Uint8Array(16);
  globalThis.crypto.getRandomValues(bytes);
  return Array.from(bytes, x => x.toString(16).padStart(2, '0')).join('');
}
export function errorMessage(error) {
  const body = error?.response?.data;
  return (
    body?.error?.message ||
    (typeof body?.error === 'string' ? body.error : null) ||
    body?.errors?.join?.('; ') ||
    error?.message ||
    'Nao foi possivel concluir a operacao.'
  );
}
export async function request(
  accountId,
  path,
  { method = 'get', data, params, key, responseType, signal } = {}
) {
  if (!/^\d+$/.test(String(accountId))) throw new Error('Conta invalida.');
  const response = await window.axios({
    method,
    url: `/api/v1/accounts/${accountId}/${path}`,
    data,
    params,
    responseType,
    ...(signal ? { signal } : {}),
    headers: key ? { 'Idempotency-Key': key } : {},
  });
  return response.data;
}
export async function allPages(accountId, path, params = {}) {
  const rows = [];
  async function loadPage(page) {
    if (page > 100) throw new Error('Limite de paginacao atingido.');
    const result = await request(accountId, path, {
      params: { ...params, page, per_page: 100 },
    });
    rows.push(...result.data);
    if (result.meta?.total > 10000)
      throw new Error(
        'Mais de 10 mil registros. Restrinja a consulta antes de abrir o quadro.'
      );
    if (!result.meta || rows.length >= result.meta.total || !result.data.length)
      return rows;
    return loadPage(page + 1);
  }
  return loadPage(1);
}
export async function downloadCsv(accountId, path, filename) {
  const blob = await request(accountId, path, { responseType: 'blob' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export const projectStatuses = {
  planned: 'Planejado',
  active: 'Em andamento',
  on_hold: 'Pausado',
  completed: 'Concluído',
  canceled: 'Cancelado',
};
export const taskStatuses = {
  backlog: 'A fazer',
  pending: 'Pendente',
  in_progress: 'Em andamento',
  review: 'Em validacao',
  completed: 'Concluído',
  blocked: 'Bloqueado',
  canceled: 'Cancelado',
  scheduled: 'Agendado',
  cancelled: 'Cancelado',
};
export const priorities = {
  low: 'Baixa',
  medium: 'Média',
  high: 'Alta',
  urgent: 'Urgente',
};
export function formatDate(value) {
  if (!value) return 'Nao definido';
  // Date-only values are not parsed as UTC, preventing the previous-day display in Brazil.
  if (/^\d{4}-\d{2}-\d{2}$/.test(value))
    return value.split('-').reverse().join('/');
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString('pt-BR');
}

export function dateInput(value = new Date()) {
  const date = new Date(value);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}
export function routeTo(name, accountId, extra = {}) {
  return { name, params: { accountId, ...extra } };
}
