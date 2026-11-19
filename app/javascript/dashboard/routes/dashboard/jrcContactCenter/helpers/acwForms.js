import {
  catalogueAnswers,
  catalogueFields,
} from 'dashboard/routes/dashboard/serviceDesk/helpers/catalogueFields';

const MAX_BYTES = 262144;
const invalid = () => {
  throw new TypeError('Invalid ACW form');
};
const bounded = value =>
  new TextEncoder().encode(JSON.stringify(value)).length <= MAX_BYTES;

// Pure native value validators only: no Service Desk context, request or permission is reused.
export function acwFormDefinition(value) {
  if (
    !value ||
    Array.isArray(value) ||
    typeof value !== 'object' ||
    Object.keys(value).length !== 1 ||
    !Object.hasOwn(value, 'fields') ||
    !bounded(value)
  )
    invalid();
  const fields = catalogueFields(value.fields);
  if (!fields.length) invalid();
  fields.forEach((field, index) => {
    if (!field.label.trim() || field.label.includes('\0')) invalid();
    if (field.type !== 'select') {
      if (Object.hasOwn(value.fields[index], 'options')) invalid();
      return;
    }
    if (
      field.options.length > 100 ||
      new Set(field.options).size !== field.options.length ||
      field.options.some(option => !option.trim() || option.includes('\0'))
    )
      invalid();
  });
  return { fields };
}

export function acwFormAnswers(definition, answers, { complete }) {
  const { fields } = acwFormDefinition(definition);
  if (
    typeof complete !== 'boolean' ||
    !answers ||
    Array.isArray(answers) ||
    typeof answers !== 'object' ||
    !bounded(answers)
  )
    invalid();
  // A native field may legitimately be called toString; inherited JS values are never answers.
  const own = Object.assign(Object.create(null), answers);
  if (
    Object.values(own).some(
      value => typeof value === 'string' && value.includes('\0')
    )
  )
    invalid();
  catalogueAnswers(
    complete ? fields : fields.map(field => ({ ...field, required: false })),
    own
  );
  if (
    complete &&
    fields.some(
      field => field.required && field.type === 'text' && !own[field.key].trim()
    )
  )
    invalid();
  return { ...own };
}
