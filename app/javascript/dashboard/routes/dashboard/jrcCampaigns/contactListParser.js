export const parseContactList = input => {
  const text = input.replace(/^\uFEFF/, '');
  const separators = { ',': 0, ';': 0, '\t': 0 };
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const char = text[i];
    if (char === '"') {
      if (quoted && text[i + 1] === '"') i += 1;
      else quoted = !quoted;
    } else if (!quoted && /[\r\n]/.test(char)) break;
    else if (!quoted && char in separators) separators[char] += 1;
  }
  const delimiter = Object.keys(separators).sort(
    (left, right) => separators[right] - separators[left]
  )[0];
  const rows = [];
  let row = [];
  let field = '';
  let closed = false;
  quoted = false;
  for (let i = 0; i <= text.length; i += 1) {
    const char = text[i];
    if (char === '"') {
      if (quoted && text[i + 1] === '"') {
        field += '"';
        i += 1;
      } else if (quoted) {
        quoted = false;
        closed = true;
      } else if (!field.trim() && !closed) quoted = true;
      else throw new Error('invalid_csv');
    } else if (
      !quoted &&
      (char === delimiter ||
        char === '\r' ||
        char === '\n' ||
        char === undefined)
    ) {
      row.push(field.trim());
      field = '';
      closed = false;
      if (char !== delimiter) {
        if (row.some(value => value)) rows.push(row);
        row = [];
        if (char === '\r' && text[i + 1] === '\n') i += 1;
      }
    } else if (char !== undefined) {
      if (closed && char.trim()) throw new Error('invalid_csv');
      field += char;
    }
  }
  if (quoted) throw new Error('invalid_csv');
  if (!rows.length) return [];
  const aliases = {
    name: ['nome', 'name'],
    phone: ['telefone', 'phone', 'phone_number', 'celular'],
    email: ['email', 'e-mail', 'e_mail'],
  };
  const header = rows[0].map(value => value.toLowerCase());
  const indexes = Object.fromEntries(
    Object.entries(aliases).map(([key, values]) => [
      key,
      header.findIndex(value => values.includes(value)),
    ])
  );
  const hasHeader = Object.values(indexes).some(index => index >= 0);
  return (hasHeader ? rows.slice(1) : rows).map(parts => {
    if (hasHeader)
      return Object.fromEntries(
        Object.entries(indexes).map(([key, index]) => [
          key,
          index >= 0 ? parts[index] || '' : '',
        ])
      );
    if (parts.length === 1)
      return parts[0].includes('@') ? { email: parts[0] } : { phone: parts[0] };
    if (parts.length === 2 && parts[1].includes('@'))
      return /^[+\d()\s-]+$/.test(parts[0])
        ? { phone: parts[0], email: parts[1] }
        : { name: parts[0], email: parts[1] };
    return { name: parts[0], phone: parts[1], email: parts[2] || '' };
  });
};
