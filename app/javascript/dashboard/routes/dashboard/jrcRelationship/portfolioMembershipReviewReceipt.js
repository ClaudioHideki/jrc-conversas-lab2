import { validMembershipCapacity } from './portfolioMembershipCapacityReceipt';
const positive = value => Number.isSafeInteger(value) && value > 0;
const revision = value => Number.isSafeInteger(value) && value >= 0;
const sameIds = (first, second) =>
  JSON.stringify([...first].sort((a, b) => a - b)) ===
  JSON.stringify([...second].sort((a, b) => a - b));

// A bare successful HTTP status cannot confirm a different group, audience or
// result. This checks the bounded native receipt, never grants source access.
export const validMembershipReview = (value, groupId, proposal = null) => {
  const input = value?.inputs;
  const items = value?.items;
  if (
    !positive(groupId) ||
    !positive(value?.id) ||
    !positive(value.revision) ||
    !/^[a-f0-9]{64}$/.test(value.digest || '') ||
    value.source_access_limited ||
    !validMembershipCapacity(value.membership_capacity, groupId) ||
    !['previewed', 'running', 'completed', 'canceled', 'attention'].includes(
      value.state
    ) ||
    input?.operation !== 'portfolio_membership' ||
    input.portfolio_group_id !== groupId ||
    !revision(input.expected_version) ||
    typeof input.active !== 'boolean' ||
    !Array.isArray(input.ids) ||
    !input.ids.length ||
    input.ids.length > 50 ||
    !input.ids.every(positive) ||
    new Set(input.ids).size !== input.ids.length ||
    !Array.isArray(items) ||
    items.length !== input.ids.length ||
    !items.every(item => item && positive(item.assignment_id)) ||
    !sameIds(
      items.map(item => item.assignment_id),
      input.ids
    ) ||
    value.summary?.portfolio_group_id !== groupId ||
    typeof value.summary.portfolio_group_name !== 'string' ||
    value.summary.active !== input.active
  )
    return false;
  if (
    proposal &&
    (proposal.operation !== 'portfolio_membership' ||
      !Array.isArray(proposal.ids) ||
      proposal.request_id !== input.request_id ||
      proposal.portfolio_group_id !== groupId ||
      proposal.active !== input.active ||
      proposal.expected_version !== input.expected_version ||
      !sameIds(proposal.ids, input.ids))
  )
    return false;

  let current = input.expected_version;
  let pendingSeen = false;
  const receiptsValid = items.every(item => {
    if (item.state !== 'applied') {
      pendingSeen = true;
      return (
        ['pending', 'failed', 'canceled'].includes(item.state) &&
        item.receipt === null
      );
    }
    if (pendingSeen) return false;
    const receipt = item.receipt;
    const changed =
      receipt?.membership_state === (input.active ? 'linked' : 'unlinked');
    const states = input.active
      ? ['linked', 'already_linked']
      : ['unlinked', 'already_unlinked'];
    const valid =
      receipt?.operation === 'portfolio_membership' &&
      receipt.assignment_id === item.assignment_id &&
      receipt.portfolio_group_id === groupId &&
      states.includes(receipt.membership_state) &&
      receipt.group_revision_before === current &&
      receipt.group_version === current + (changed ? 1 : 0);
    if (valid) current = receipt.group_version;
    return valid;
  });
  if (!receiptsValid) return false;
  if (value.state === 'previewed')
    return items.every(item => item.state === 'pending');
  if (value.state === 'completed')
    return items.every(item => item.state === 'applied');
  if (value.state === 'running')
    return items.some(item => item.state === 'pending');
  return items.every(item => item.state !== 'pending');
};
