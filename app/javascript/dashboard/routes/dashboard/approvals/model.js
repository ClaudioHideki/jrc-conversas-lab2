/* global BigInt */
export const STATES = [
  'pending',
  'approved',
  'rejected',
  'returned',
  'escalated',
  'expired',
  'canceled',
  'stale',
];
export const OPERATORS = {
  integer: ['eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'between', 'in'],
  decimal: ['eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'between', 'in'],
  money: ['eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'between', 'in'],
  datetime: ['eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'between', 'in'],
  string: ['eq', 'neq', 'contains', 'in'],
  boolean: ['eq', 'neq'],
};
export const copy = value => JSON.parse(JSON.stringify(value));
export const emptyDefinition = () => ({
  schema_version: 1,
  condition: { const: false },
  selection: { mode: '', priority: null },
  execution: '',
  completion: 'all_steps',
  steps: [],
  expires_in_seconds: null,
  allow_self_approval: false,
  delegation_allowed: false,
  reopen_mode: 'disabled',
});
export const emptyStep = () => ({
  code: '',
  mode: '',
  quorum: null,
  assignees: [],
  authority: { const: false },
  actions: ['approved'],
  on_reject: '',
});
export const moneyCents = text => {
  if (!/^-?\d+(\.\d{1,2})?$/.test(text)) throw new Error('INVALID_TYPED_VALUE');
  const negative = text.startsWith('-');
  const [whole, part = ''] = text.replace('-', '').split('.');
  const cents = BigInt(whole) * 100n + BigInt(part.padEnd(2, '0'));
  const value = Number(negative ? -cents : cents);
  if (!Number.isSafeInteger(value)) throw new Error('INVALID_TYPED_VALUE');
  return value;
};
export const parseValue = (type, text, currency) => {
  if (type === 'money') {
    if (!/^[A-Z]{3}$/.test(currency)) throw new Error('INVALID_TYPED_VALUE');
    return { amount_cents: moneyCents(text), currency };
  }
  if (type === 'integer') {
    if (!/^-?\d+$/.test(text) || !Number.isSafeInteger(Number(text)))
      throw new Error('INVALID_TYPED_VALUE');
    return Number(text);
  }
  if (type === 'decimal') {
    if (!/^-?\d+(\.\d+)?$/.test(text) || text.length > 100)
      throw new Error('INVALID_TYPED_VALUE');
    return text;
  }
  if (type === 'boolean') {
    if (!['true', 'false'].includes(text))
      throw new Error('INVALID_TYPED_VALUE');
    return text === 'true';
  }
  if (
    type === 'datetime' &&
    (!/(Z|[+-]\d{2}:\d{2})$/.test(text) || Number.isNaN(Date.parse(text)))
  )
    throw new Error('INVALID_TYPED_VALUE');
  return text;
};
export const conditionCount = node =>
  1 +
  (node.all || node.any || []).reduce(
    (n, child) => n + conditionCount(child),
    0
  );
export const pagination = response => ({
  total: Number(response.headers['x-total-count'] || 0),
  page: Number(response.headers['x-page'] || 1),
  limit: Number(response.headers['x-per-page'] || 25),
});
export const capability = (context, action, company, unit) =>
  (context?.scopes || []).some(
    scope =>
      scope.capabilities.includes(action) &&
      (company === undefined || scope.issuer_company_id === company) &&
      (unit === undefined || scope.business_unit_id === unit)
  );
export const decisionChoices = dto =>
  (dto?.allowed_decisions || []).flatMap(step =>
    step.choices.flatMap(choice =>
      choice.actions.map(action => ({
        step_code: step.step_code,
        decision: action,
        delegation_id: choice.delegation_id,
      }))
    )
  );
export const intent = () => {
  let previous;
  return (body, scope = '') => {
    const content = JSON.stringify([scope, body]);
    if (previous?.content !== content)
      previous = { content, key: crypto.randomUUID() };
    return { ...body, idempotency_key: previous.key };
  };
};
export const auditPresentation = event => ({
  id: event.id,
  event: event.event_type,
  actor: event.actor_id,
  at: event.created_at,
  reason: event.data?.reason,
  state: event.data?.state,
  version: event.data?.expected_version,
  cycle: event.data?.cycle,
});

export const describeCondition = node => {
  if (Object.hasOwn(node, 'const')) return String(node.const);
  const group = node.all ? 'all' : 'any';
  if (node[group])
    return `${group.toUpperCase()} (${node[group].map(describeCondition).join('; ')})`;
  const display = value =>
    value && typeof value === 'object'
      ? `${value.amount_cents} cents ${value.currency}`
      : String(value);
  return `${node.field} ${node.op} ${(Array.isArray(node.value) ? node.value : [node.value]).map(display).join(' / ')}`;
};

export const scopeLabel = (context, record) => {
  const scope = context?.scopes.find(
    row =>
      row.issuer_company_id === record.issuer_company_id &&
      row.business_unit_id === record.business_unit_id
  );
  return [
    scope?.company_name || record.issuer_company_id,
    scope?.unit_name || record.business_unit_id,
  ]
    .filter(Boolean)
    .join(' / ');
};
