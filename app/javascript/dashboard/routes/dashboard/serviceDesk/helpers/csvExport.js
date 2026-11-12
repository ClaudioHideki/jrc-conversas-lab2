export function csvText(rows) {
  const cell = value => {
    const text =
      value === null || value === undefined
        ? ''
        : String(value).replaceAll('\u0000', '');
    const safe =
      /^[\s]*[=+@-]/.test(text) || /^[\t\r\n]/.test(text) ? `'${text}` : text;
    return `"${safe.replaceAll('"', '""')}"`;
  };
  return (
    '\uFEFF' + rows.map(row => row.map(cell).join(',')).join('\r\n') + '\r\n'
  );
}
export function downloadCsv(rows, filename) {
  const href = URL.createObjectURL(
    new Blob([csvText(rows)], { type: 'text/csv;charset=utf-8' })
  );
  const link = document.createElement('a');
  link.href = href;
  link.download = filename;
  link.click();
  window.setTimeout(() => URL.revokeObjectURL(href), 1000);
}
export function metricRows(value, path = '') {
  if (value === null || typeof value !== 'object') return [[path, value]];
  return Object.entries(value).flatMap(([key, item]) =>
    metricRows(item, path ? `${path}.${key}` : key)
  );
}
