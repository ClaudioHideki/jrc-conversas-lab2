// UI routes only. No role/capability grants or domain records live in this map.
export const SERVICE_DESK_ROUTES = Object.freeze([
  { key: 'overview', path: '', page: 'overview', icon: 'i-lucide-layout-dashboard', group: 'operation' },
  { key: 'tickets', path: 'tickets', page: 'tickets', icon: 'i-lucide-ticket', group: 'operation', resource: 'tickets' },
  { key: 'mine', path: 'my-queue', page: 'tickets', icon: 'i-lucide-list-checks', group: 'operation', resource: 'tickets' },
  { key: 'new', path: 'tickets/new', page: 'form', icon: 'i-lucide-plus', group: 'operation', resource: 'tickets' },
  { key: 'detail', path: 'tickets/:ticketId(\\d+)', page: 'detail', resource: 'tickets' },
  { key: 'edit', path: 'tickets/:ticketId(\\d+)/edit', page: 'form', resource: 'tickets' },
  { key: 'queues', path: 'queues', page: 'catalog', icon: 'i-lucide-users', group: 'operation', resource: 'queues' },
  { key: 'assignees', path: 'assignees', page: 'catalog', icon: 'i-lucide-user-round-check', group: 'operation', resource: 'assignees' },
  { key: 'sla', path: 'sla', page: 'planned', icon: 'i-lucide-timer', group: 'governance' },
  { key: 'catalog', path: 'catalog', page: 'planned', icon: 'i-lucide-layers', group: 'governance' },
  { key: 'knowledge', path: 'knowledge', page: 'planned', icon: 'i-lucide-book-open', group: 'governance' },
  { key: 'approvals', path: 'approvals', page: 'planned', icon: 'i-lucide-badge-check', group: 'governance' },
  { key: 'problems', path: 'problems', page: 'planned', icon: 'i-lucide-circle-alert', group: 'governance' },
  { key: 'changes', path: 'changes', page: 'planned', icon: 'i-lucide-git-pull-request', group: 'governance' },
  { key: 'assets', path: 'assets', page: 'planned', icon: 'i-lucide-monitor', group: 'governance' },
  { key: 'contracts', path: 'contracts', page: 'planned', icon: 'i-lucide-file-text', group: 'governance' },
  { key: 'automations', path: 'automations', page: 'planned', icon: 'i-lucide-workflow', group: 'management' },
  { key: 'surveys', path: 'surveys', page: 'planned', icon: 'i-lucide-smile', group: 'management' },
  { key: 'reports', path: 'reports', page: 'planned', icon: 'i-lucide-chart-no-axes-combined', group: 'management' },
  { key: 'settings', path: 'settings', page: 'settings', icon: 'i-lucide-settings', group: 'management' },
  { key: 'priorities', path: 'settings/priorities', page: 'catalog', resource: 'priorities' },
  { key: 'categories', path: 'settings/categories', page: 'catalog', resource: 'categories' },
  { key: 'statuses', path: 'settings/statuses', page: 'catalog', resource: 'statuses' },
  { key: 'units', path: 'settings/units', page: 'catalog', resource: 'units' },
  { key: 'operator_companies', path: 'settings/operator-companies', page: 'catalog', resource: 'operator_companies' },
]);
export const serviceDeskRouteName = key => `jrc_service_desk_${key}`;
export const CORE_CATALOGS = Object.freeze([
  'queues', 'priorities', 'categories', 'statuses', 'units',
  'operator_companies', 'assignees',
]);
