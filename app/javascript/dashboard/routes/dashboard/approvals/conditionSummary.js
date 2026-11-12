// Presentation only. Native typed nodes and authorization are never changed here.
export const conditionSummary = (node, t) => {
  if (Object.hasOwn(node, 'const'))
    return t(`JRC_APPROVALS.conditionGroup.${node.const ? 'always' : 'never'}`);
  const group = node.all ? 'all' : 'any';
  if (node[group])
    return `${t(`JRC_APPROVALS.conditionGroup.${group}`)} (${node[group].map(child => conditionSummary(child, t)).join('; ')})`;
  const display = value => {
    if (value && typeof value === 'object')
      return `${value.amount_cents} / 100 ${value.currency}`;
    if (typeof value === 'boolean')
      return t(`JRC_APPROVALS.conditionGroup.${value ? 'yes' : 'no'}`);
    return String(value);
  };
  return `${t(`JRC_APPROVALS.catalogFields.${node.field}`)} ${t(`JRC_APPROVALS.operators.${node.op}`)} ${(Array.isArray(node.value) ? node.value : [node.value]).map(display).join(' / ')}`;
};
