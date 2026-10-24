// One confirmation, followed only by the official, freshly authorized commands.
export function requiredClosureFields(plan) {
  const result = [];
  (plan?.steps || []).forEach(step => {
    Object.entries(step.requirements.fields || {}).forEach(([key, spec]) => {
      if (
        key === 'closing_reason' &&
        spec.type === 'text' &&
        !Object.hasOwn(spec, 'equals')
      )
        return;
      if (!spec.required && !Object.hasOwn(spec, 'equals')) return;
      const previous = result.find(
        row =>
          row.key === key && JSON.stringify(row.spec) === JSON.stringify(spec)
      );
      if (previous) previous.rules.push(step.key);
      else
        result.push({
          key,
          spec,
          rules: [step.key],
          input: `${step.key}:${key}`,
        });
    });
  });
  return result;
}
export function closureCommand(rule, data, draft, requiredFields) {
  return {
    rule_key: rule.key,
    expected_lock_version: data.lock_version,
    expected_policy_version_id: data.policy.id,
    closing_reason: draft.reason,
    ...(rule.requirements.solution ? { solution: draft.solution } : {}),
    ...(rule.requirements.note ? { note: draft.note } : {}),
    evidence_note_ids: rule.requirements.evidence
      ? draft.evidence.split(',').map(value => value.trim())
      : [],
    fields: Object.fromEntries(
      [
        ...requiredFields,
        ...(rule.requirements.fields?.closing_reason?.type === 'text' &&
        !Object.hasOwn(rule.requirements.fields.closing_reason, 'equals')
          ? [
              {
                key: 'closing_reason',
                rules: [rule.key],
                spec: { type: 'text' },
                reason: true,
              },
            ]
          : []),
      ]
        .filter(row => row.rules.includes(rule.key))
        .map(row => {
          let value = draft.fields[row.input];
          if (row.reason) value = draft.reason;
          else if (row.spec.type === 'integer') value = Number(value);
          return [row.key, value];
        })
    ),
  };
}
