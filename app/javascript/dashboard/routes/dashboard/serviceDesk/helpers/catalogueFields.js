import { canonicalId } from './access';

export function catalogueFields(value = []) {
  if (!Array.isArray(value) || value.length > 50)
    throw new TypeError('Invalid catalogue fields');
  const rows = value.map(field => {
    if (
      !field ||
      typeof field !== 'object' ||
      Array.isArray(field) ||
      Object.keys(field).some(
        key => !['key', 'label', 'type', 'required', 'options'].includes(key)
      )
    )
      throw new TypeError('Invalid catalogue field');
    if (
      typeof field.key !== 'string' ||
      !/^[A-Za-z0-9_.-]{1,80}$/.test(field.key) ||
      ['__proto__', 'constructor', 'prototype'].includes(field.key)
    )
      throw new TypeError('Invalid field key');
    if (
      typeof field.label !== 'string' ||
      !field.label.length ||
      field.label.length > 255 ||
      !['text', 'integer', 'boolean', 'select'].includes(field.type) ||
      typeof field.required !== 'boolean'
    )
      throw new TypeError('Invalid field type');
    if (
      field.type === 'select' &&
      (!Array.isArray(field.options) ||
        !field.options.length ||
        !field.options.every(
          item =>
            typeof item === 'string' && item.length > 0 && item.length <= 255
        ))
    )
      throw new TypeError('Invalid field options');
    return {
      key: field.key,
      label: field.label,
      type: field.type,
      required: field.required,
      ...(field.type === 'select' ? { options: [...field.options] } : {}),
    };
  });
  if (new Set(rows.map(row => row.key)).size !== rows.length)
    throw new TypeError('Duplicate field key');
  return rows;
}
export function decodeCatalogueForm(payload, context, selection) {
  const check = value => {
    if (!value) throw new TypeError('Invalid catalogue context');
  };
  check(
    payload?.contract_version === 1 &&
      payload.account_id === context.account_id &&
      payload.unit_id === selection.unit_id
  );
  check(
    context.units.some(unit => unit.id === selection.unit_id) &&
      /^[a-f0-9]{64}$/.test(payload.revision)
  );
  const named = value => {
    if (value === null) return null;
    check(value && canonicalId(value.id) && typeof value.name === 'string');
    return { id: canonicalId(value.id), name: value.name };
  };
  const result = {
    form_fields: catalogueFields(payload.form_fields),
    revision: payload.revision,
  };
  ['service', 'ticket_type', 'category', 'subcategory'].forEach(key => {
    result[key] = named(payload[key]);
    if (Object.hasOwn(selection, `${key}_id`))
      check((result[key]?.id || null) === selection[`${key}_id`]);
  });
  result.defaults = {};
  ['priority', 'queue', 'assignee'].forEach(key => {
    const field = key === 'assignee' ? 'assignee_account_user_id' : `${key}_id`;
    const value = payload.defaults?.[field];
    check(value === null || canonicalId(value));
    result.defaults[field] = value === null ? null : canonicalId(value);
    result.defaults[key] =
      payload.defaults?.[key] == null ? null : named(payload.defaults[key]);
    if (result.defaults[key])
      check(result.defaults[key].id === result.defaults[field]);
  });
  ['allowed_company_ids', 'allowed_contract_ids'].forEach(key => {
    const values = payload[key] || [];
    check(Array.isArray(values) && values.length <= 100);
    const ids = values.map(canonicalId);
    check(ids.every(Boolean) && new Set(ids).size === ids.length);
    result[key] = ids;
  });
  return result;
}
export function catalogueAnswers(fields, answers) {
  if (
    !answers ||
    typeof answers !== 'object' ||
    Array.isArray(answers) ||
    Object.keys(answers).some(key => !fields.some(row => row.key === key))
  )
    throw new TypeError('Unknown service answer');
  fields.forEach(field => {
    const value = answers[field.key];
    if (
      field.required &&
      (value === null || value === undefined || value === '')
    )
      throw new TypeError('Required field missing');
    if (value === undefined || value === null) return;
    const validators = {
      text: item => typeof item === 'string' && item.length <= 4000,
      integer: Number.isSafeInteger,
      boolean: item => typeof item === 'boolean',
      select: item => field.options.includes(item),
    };
    const valid = validators[field.type](value);
    if (!valid) throw new TypeError('Invalid service answer');
  });
  return { ...answers };
}
export function retainedCatalogueAnswers(fields, answers) {
  const result = {};
  fields.forEach(field => {
    if (!Object.hasOwn(answers, field.key)) return;
    try {
      catalogueAnswers([{ ...field, required: false }], {
        [field.key]: answers[field.key],
      });
      result[field.key] = answers[field.key];
    } catch {
      /* An answer cannot migrate to a different configured type. */
    }
  });
  return result;
}
