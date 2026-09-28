// Synthetic fixtures live ONLY in tests and are never imported by application code.
export const identity = { accountId: '1', userId: '7', enabled: true };
export const contextPayload = (overrides = {}) => ({
  contract_version: 1, account_id: '1', user_id: '7', available: true,
  units: [
    { id: '10', account_id: '1', active: true, name: 'Test unit A', operator_company: { id: '3', account_id: '1', name: 'Test operator' }, permissions: { create_ticket: true, assign_ticket: true, link_conversation: true } },
    { id: '11', account_id: '1', active: true, name: 'Test unit B', operator_company: { id: '4', account_id: '1', name: 'Other test operator' }, permissions: {} },
  ],
  capabilities: Object.fromEntries(['module', 'dashboard', 'tickets', 'priorities', 'statuses', 'queues', 'categories', 'units', 'operator_companies', 'assignees', 'requesters', 'teams'].map(name => [name, { index: true }])),
  ...overrides,
});
export const ticket = (overrides = {}) => ({
  id: '20', account_id: '1', unit_id: '10', title: 'Synthetic test ticket', description: 'Test-only text',
  number: 'TEST-20', permissions: { show: true, update: true, change_priority: true, view_notes: true, view_history: true, view_conversations: true, view_sla: true, view_customer: true },
  status: { id: '1', name: 'Test status' }, priority: { id: '2', name: 'Test priority' },
  requester: { id: '33', name: 'Test requester' }, created_at: '2026-09-25T10:00:00Z', updated_at: '2026-09-25T12:00:00Z',
  ...overrides,
});
export const collection = (items = [ticket()], overrides = {}) => ({
  contract_version: 1, account_id: '1', items, meta: { page: 1, per_page: 20, total: items.length }, ...overrides,
});
export const detail = (value = ticket()) => ({ contract_version: 1, account_id: '1', ticket: value });
export const deferred = () => { let resolve; let reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return { promise, resolve, reject }; };
export const httpError = status => ({ response: { status } });
export const fakeClient = (overrides = {}) => ({
  context: async () => contextPayload(), list: async () => collection(), ticket: async () => detail(), ...overrides,
});
