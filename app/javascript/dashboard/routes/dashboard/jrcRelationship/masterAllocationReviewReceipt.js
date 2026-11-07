const positive = value => Number.isSafeInteger(value) && value > 0;
const revision = value => Number.isSafeInteger(value) && value >= 0;
const digest = value => /^[a-f0-9]{64}$/.test(value || '');
const canonical = value => {
  if (Array.isArray(value)) return value.map(canonical);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(
    Object.keys(value)
      .sort()
      .map(key => [key, canonical(value[key])])
  );
};
const same = (first, second) =>
  JSON.stringify(canonical(first)) === JSON.stringify(canonical(second));
const ordered = rows => [...rows].sort((a, b) => a - b);

// A later successful response cannot replace the already reviewed decision or
// an applied item while keeping the same immutable review identity.
export const validMasterTransition = (previous, value) => {
  if (!previous || previous.id !== value.id) return true;
  if (previous.revision > value.revision) return true;
  if (
    !['digest', 'inputs', 'summary', 'expires_at'].every(key =>
      same(previous[key], value[key])
    )
  )
    return false;
  if (previous.items.length !== value.items.length) return false;
  return previous.items.every((item, index) => {
    const next = value.items[index];
    if (
      !['company_id', 'mode', 'label', 'allocation'].every(key =>
        same(item[key], next[key])
      )
    )
      return false;
    if (item.state === 'pending') return true;
    return ['state', 'assignment_id', 'receipt', 'error_code'].every(key =>
      same(item[key], next[key])
    );
  });
};
const facts = [
  'current',
  'incoming',
  'projected',
  'effective_capacity',
  'available_after',
];
const blockers = [
  'capacity_missing',
  'capacity_workload_missing',
  'capacity_scope_denied',
  'controlled_review_required',
];
export const validMasterCapacity = value =>
  value &&
  ['not_configured', 'projected'].includes(value.state) &&
  Array.isArray(value.rows) &&
  value.rows.length <= 1000 &&
  (value.state === 'not_configured'
    ? value.rows.length === 0
    : value.rows.length > 0) &&
  value.rows.every(row => {
    if (
      !positive(row?.user_id) ||
      !positive(row.configuration_version) ||
      !/^(account|(unit|company|team|segment|product|portfolio):[1-9]\d*)$/.test(
        row.scope_key
      ) ||
      !['customers', 'points', 'hours'].includes(row.unit) ||
      Object.hasOwn(row, 'source_assignment_ids') ||
      Object.hasOwn(row, 'baseline_digest')
    )
      return false;
    if (blockers.includes(row.blocker))
      return facts.every(key => !Object.hasOwn(row, key));
    return (
      [null, 'capacity_owner_unavailable', 'capacity_exceeded'].includes(
        row.blocker
      ) &&
      facts.every(
        key => typeof row[key] === 'number' && Number.isFinite(row[key])
      ) &&
      row.current >= 0 &&
      row.incoming >= 0 &&
      row.projected >= 0 &&
      row.effective_capacity >= 0
    );
  });

// Separate subject contract: pending companies have no allocation ID. Never
// weaken the existing allocation-only membership receipt validator.
export const validMasterAllocationReview = (
  value,
  groupId,
  proposal = null
) => {
  const input = value?.inputs;
  const items = value?.items;
  if (
    !positive(groupId) ||
    !positive(value?.id) ||
    !positive(value.revision) ||
    !digest(value.digest) ||
    value.source_access_limited ||
    !validMasterCapacity(value.master_capacity) ||
    !['previewed', 'running', 'completed', 'canceled', 'attention'].includes(
      value.state
    ) ||
    input?.operation !== 'master_allocation' ||
    input.portfolio_group_id !== groupId ||
    !revision(input.expected_version) ||
    !Array.isArray(input.ids) ||
    !input.ids.length ||
    input.ids.length > 50 ||
    !input.ids.every(positive) ||
    new Set(input.ids).size !== input.ids.length ||
    !Array.isArray(input.creations) ||
    input.creations.length > 50 ||
    !Array.isArray(items) ||
    items.length !== input.ids.length ||
    !items.every(
      item =>
        item &&
        positive(item.company_id) &&
        ['create', 'reuse'].includes(item.mode) &&
        item.allocation &&
        ['owner_id', 'team_id', 'business_unit_id'].every(
          key => item.allocation[key] === null || positive(item.allocation[key])
        )
    ) ||
    !same(ordered(items.map(item => item.company_id)), ordered(input.ids)) ||
    value.summary?.portfolio_group_id !== groupId ||
    typeof value.summary.portfolio_group_name !== 'string' ||
    value.summary.create_count !==
      items.filter(item => item.mode === 'create').length ||
    value.summary.reuse_count !==
      items.filter(item => item.mode === 'reuse').length
  )
    return false;
  if (proposal) {
    const fields = [
      'operation',
      'request_id',
      'portfolio_group_id',
      'expected_version',
      'justification',
      'previous_review_id',
    ];
    if (
      fields.some(key => proposal[key] !== input[key]) ||
      !Array.isArray(proposal.ids) ||
      !same(ordered(proposal.ids), ordered(input.ids)) ||
      !same(
        [...(proposal.creations || [])].sort(
          (a, b) => a.company_id - b.company_id
        ),
        input.creations
      )
    )
      return false;
  }
  let current = input.expected_version;
  let pendingSeen = false;
  const receipts = items.every(item => {
    if (item.state !== 'applied') {
      pendingSeen = true;
      return (
        ['pending', 'failed', 'canceled'].includes(item.state) &&
        item.assignment_id === null &&
        item.receipt === null
      );
    }
    if (pendingSeen || !positive(item.assignment_id)) return false;
    const receipt = item.receipt;
    const changed = receipt?.membership_state === 'linked';
    const valid =
      receipt?.operation === 'master_allocation' &&
      receipt.updated === 1 &&
      receipt.company_id === item.company_id &&
      receipt.assignment_id === item.assignment_id &&
      receipt.portfolio_group_id === groupId &&
      receipt.allocation_state ===
        (item.mode === 'create' ? 'created' : 'reused') &&
      digest(receipt.assignment_digest) &&
      ['linked', 'already_linked'].includes(receipt.membership_state) &&
      receipt.group_revision_before === current &&
      receipt.group_version === current + (changed ? 1 : 0);
    if (valid) current = receipt.group_version;
    return valid;
  });
  if (!receipts) return false;
  const allocationIds = items
    .filter(item => item.state === 'applied')
    .map(item => item.assignment_id);
  if (new Set(allocationIds).size !== allocationIds.length) return false;
  if (value.state === 'previewed')
    return items.every(item => item.state === 'pending');
  if (value.state === 'completed')
    return items.every(item => item.state === 'applied');
  if (value.state === 'running')
    return (
      items.every(item => ['pending', 'applied'].includes(item.state)) &&
      items.some(item => item.state === 'pending')
    );
  return items.every(item => item.state !== 'pending');
};
