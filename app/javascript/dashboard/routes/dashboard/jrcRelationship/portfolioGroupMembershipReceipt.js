export const confirmedMembership = (data, request) => {
  const ids = request.assignment_ids.map(Number);
  const allowed = request.active
    ? ['linked', 'already_linked']
    : ['unlinked', 'already_unlinked'];
  const results = data?.results;
  if (
    !Array.isArray(results) ||
    results.length !== ids.length ||
    new Set(ids).size !== ids.length
  )
    return false;
  if (
    !results.every(
      row =>
        row &&
        Number.isSafeInteger(row.assignment_id) &&
        ids.includes(row.assignment_id) &&
        allowed.includes(row.state)
    )
  )
    return false;
  if (new Set(results.map(row => row.assignment_id)).size !== ids.length)
    return false;
  const changed = results.some(
    row => row.state === 'linked' || row.state === 'unlinked'
  );
  return data.version === request.expected_version + (changed ? 1 : 0);
};
