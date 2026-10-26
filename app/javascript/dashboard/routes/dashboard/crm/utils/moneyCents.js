/* global BigInt */
export function moneyCents(value) {
  let input = String(value ?? '').trim();
  if (!input) return 0;
  if (input.includes(',')) input = input.replaceAll('.', '').replace(',', '.');
  const match = /^(\d+)(?:\.(\d*))?$/.exec(input);
  if (!match) throw new Error('Valor monetário inválido.');
  const decimal = (match[2] || '').padEnd(3, '0');
  const result =
    BigInt(match[1]) * 100n +
    BigInt(decimal.slice(0, 2)) +
    (Number(decimal[2]) >= 5 ? 1n : 0n);
  if (result > BigInt(Number.MAX_SAFE_INTEGER))
    throw new Error('Valor monetário fora do limite seguro.');
  return Number(result);
}

export function centsInput(value) {
  const cents = Number(value || 0);
  if (!Number.isSafeInteger(cents) || cents < 0)
    throw new Error('Valor em centavos inválido.');
  return `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;
}
