/* global BigInt */
// Same 0–100 range and HALF_UP minor-unit rounding as CommercialFinancials.
// This is an input conversion for the installed discount_cents field only.
export const percentageDiscountCents = (base, text) => {
  if (!Number.isSafeInteger(base) || base <= 0)
    throw new Error('A positive exact native discount base is required');
  if (typeof text !== 'string') throw new Error('Enter a percentage as text');
  const value = String(text).trim().replace(',', '.');
  if (!/^(?:0|[1-9]\d{0,2})(?:\.\d{1,4})?$/.test(value))
    throw new Error('Enter a percentage with at most four decimal places');
  const [whole, fraction = ''] = value.split('.');
  const rate = BigInt(whole) * 10000n + BigInt(fraction.padEnd(4, '0'));
  if (rate > 1000000n) throw new Error('Percentage must be from 0 to 100');
  return Number((BigInt(base) * rate + 500000n) / 1000000n);
};
