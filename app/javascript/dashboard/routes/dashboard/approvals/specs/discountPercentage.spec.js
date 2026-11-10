import { expect, it } from 'vitest';
import vectors from '../../../../../../../spec/fixtures/jrc_approvals/discount_percentage_examples.json';
import { percentageDiscountCents } from '../discountPercentage';

it.each(vectors)(
  'matches native rounding for $percent percent of $base_cents minor units',
  example => {
    expect(percentageDiscountCents(example.base_cents, example.percent)).toBe(
      example.discount_cents
    );
  }
);

it('accepts a decimal comma and zero while rejecting invalid precision, unsafe bases and ambiguous formats', () => {
  expect(percentageDiscountCents(12345, '12,3456')).toBe(1524);
  expect(percentageDiscountCents(800, '0')).toBe(0);
  [
    '',
    ' ',
    '-1',
    '100.0001',
    '0.00001',
    '1e2',
    '20%',
    'NaN',
    'Infinity',
    '1,2,3',
    null,
    [20],
  ].forEach(value => {
    expect(() => percentageDiscountCents(800, value)).toThrow();
  });
  [0, -1, null, 1.5, Number.MAX_SAFE_INTEGER + 1].forEach(base => {
    expect(() => percentageDiscountCents(base, '20')).toThrow();
  });
});
