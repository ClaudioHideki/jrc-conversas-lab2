// RFC4180 comma-separated files, including quoted newlines and escaped quotes.
export const parseMigrationFile = (text, filename) => {
  if (filename.toLowerCase().endsWith('.json')) {
    const rows = JSON.parse(text);
    if (!Array.isArray(rows)) throw new Error('Invalid rows');
    return rows;
  }
  if (!filename.toLowerCase().endsWith('.csv'))
    throw new Error('Invalid format');
  const lines = [];
  let row = [];
  let value = '';
  let quoted = false;
  let closedQuote = false;
  const source = text.replace(/^\uFEFF/, '');
  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (char === '"') {
      if (quoted && source[index + 1] === '"') {
        value += '"';
        index += 1;
      } else if (quoted) {
        quoted = false;
        closedQuote = true;
      } else {
        if (value.length || closedQuote) throw new Error('Invalid quote');
        quoted = true;
      }
    } else if (!quoted && (char === ',' || char === '\n' || char === '\r')) {
      row.push(value);
      value = '';
      closedQuote = false;
      if (char !== ',') {
        lines.push(row);
        row = [];
        if (char === '\r' && source[index + 1] === '\n') index += 1;
      }
    } else {
      if (closedQuote) throw new Error('Invalid text after quote');
      value += char;
    }
  }
  if (quoted) throw new Error('Unclosed quote');
  if (value || row.length) lines.push([...row, value]);
  const headers = lines.shift();
  if (
    !headers?.length ||
    headers.some(key => !key) ||
    new Set(headers).size !== headers.length
  ) {
    throw new Error('Invalid headers');
  }
  return lines
    .filter(values => values.some(Boolean))
    .map(values => {
      if (values.length !== headers.length) throw new Error('Invalid columns');
      return Object.fromEntries(
        headers.map((key, index) => [key, values[index]])
      );
    });
};
