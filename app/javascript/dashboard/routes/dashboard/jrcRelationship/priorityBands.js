export const priorityCodes = ['P0', 'P1', 'P2', 'P3'];

export const validPriorityBands = bands =>
  Array.isArray(bands) &&
  (bands.length === 0 ||
    (bands.length === 4 &&
      bands.every(
        (row, index) =>
          row?.code === priorityCodes[index] &&
          Object.keys(row).sort().join(',') === 'code,minimum' &&
          Number.isInteger(row.minimum) &&
          row.minimum >= 0 &&
          row.minimum <= 100 &&
          (index === 0 || bands[index - 1].minimum > row.minimum)
      ) &&
      bands[3].minimum === 0));

export const capturedPriorityBand = record => {
  const factors = record?.factors;
  return priorityCodes.includes(factors?.priority_band) &&
    factors.priority_band_score === record.priority
    ? factors.priority_band
    : '';
};
