import { describe, expect, it } from 'vitest';
import { centsInput, moneyCents } from '../moneyCents';

describe('proposal decimal money in integer cents', () => {
  it.each([
    ['295.00', 29500],
    ['295,00', 29500],
    ['1.234,56', 123456],
    ['1.005', 101],
    ['0.29', 29],
    ['', 0],
  ])('converts %s without binary floating point rounding', (input, cents) => {
    expect(moneyCents(input)).toBe(cents);
    expect(moneyCents(centsInput(cents))).toBe(cents);
  });
  it.each(['-1', 'NaN', 'Infinity', '90071992547409999.99'])(
    'rejects invalid or unsafe amount %s',
    input => expect(() => moneyCents(input)).toThrow()
  );
  it('retains exact cents at the safe integer boundary', () =>
    expect(centsInput(Number.MAX_SAFE_INTEGER)).toBe('90071992547409.91'));
});
