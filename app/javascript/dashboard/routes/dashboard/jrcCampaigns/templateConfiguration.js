export const variables = text => [
  ...new Set(
    [...String(text || '').matchAll(/\{\{\s*([^{}]+?)\s*\}\}/g)].map(
      match => match[1]
    )
  ),
];

export const templateParts = template => {
  const components = template?.components || [];
  return {
    header: components.find(item => item.type?.toUpperCase() === 'HEADER'),
    body: components.find(item => item.type?.toUpperCase() === 'BODY'),
    footer: components.find(item => item.type?.toUpperCase() === 'FOOTER'),
    buttons:
      components.find(item => item.type?.toUpperCase() === 'BUTTONS')
        ?.buttons || [],
  };
};

export const templateErrors = (template, params) => {
  if (!template || template.status?.toUpperCase() !== 'APPROVED')
    return ['TEMPLATE'];
  if (!params || Array.isArray(params) || typeof params !== 'object')
    return ['JSON'];
  const processed = params.processed_params || {};
  if (!processed || Array.isArray(processed) || typeof processed !== 'object')
    return ['JSON'];
  const errors = [];
  const parts = templateParts(template);
  const sections = (template.components || []).map(component =>
    component.type?.toLowerCase()
  );
  Object.entries(processed).forEach(([key, value]) => {
    const populated = value && Object.keys(value).length > 0;
    if (
      !['header', 'body', 'buttons'].includes(key) ||
      (populated && !sections.includes(key))
    )
      errors.push('JSON');
  });
  (template.components || []).forEach(component => {
    if (
      !['HEADER', 'BODY', 'FOOTER', 'BUTTONS'].includes(
        component.type?.toUpperCase()
      )
    )
      errors.push('UNSUPPORTED');
  });
  ['header', 'body'].forEach(key => {
    const component = parts[key];
    if (!component) return;
    if (key === 'header' && component.format?.toUpperCase() !== 'TEXT') {
      const kind = component.format?.toLowerCase();
      if (!['image', 'video', 'document'].includes(kind))
        errors.push('UNSUPPORTED');
      else if (
        processed.header?.media_type !== kind ||
        !processed.header?.media_asset_id
      )
        errors.push('MEDIA');
    } else {
      variables(component.text).forEach(name => {
        if (!String(processed[key]?.[name] || '').trim())
          errors.push(`${key}:${name}`);
      });
    }
  });
  parts.buttons.forEach((button, index) => {
    if (!['URL', 'PHONE_NUMBER', 'QUICK_REPLY'].includes(button.type))
      errors.push('UNSUPPORTED');
    if (
      button.type === 'URL' &&
      variables(button.url).length &&
      !processed.buttons?.[index]?.parameter?.trim()
    )
      errors.push(`button:${index}`);
  });
  return errors;
};

export const parseTemplateJson = text => {
  const result = JSON.parse(text || '{}');
  if (!result || Array.isArray(result) || typeof result !== 'object')
    throw new Error('JSON');
  return result;
};
