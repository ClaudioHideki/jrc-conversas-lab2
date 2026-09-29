import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const path = new URL('../../app/javascript/dashboard/routes/dashboard/crm/helpers/commercialTerms.js', import.meta.url);
const source = await readFile(path, 'utf8');
const { proposalToOrderForm, orderFinancialPayload } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const fixture = () => ({ id: 44, customer: { id: 7, name: 'Cliente JRC' }, owner: { id: 3 }, deal_id: 9,
  financials: { payment_condition: 'down_payment_installments', payment_method: 'boleto', installments_count: 7,
    down_payment_cents: 30000, shipping_cents: 12345, shipping_mode: 'separate', shipping_in_installments: false,
    has_monthly_fee: false, first_due_date: '2026-09-29', discount_cents: 123 },
  items: [{ product_id: 2, name_snapshot: 'Servico', quantity: 2, unit_price_cents: 9999, discount_cents: 123,
    billing_model: 'monthly', setup_fee_cents: 500, initial_total_cents: 20375, recurring_total_cents: 19875,
    included_quantity: 20, included_unit: 'ramais', overage_unit_price_cents: 10, activation_days: 2, validation_period_days: 7 }] });
test('hydrate exact accepted terms including explicit false values', () => {
  const form = proposalToOrderForm(fixture());
  assert.equal(form.shipping_in_installments, false); assert.equal(form.has_monthly_fee, false);
  assert.equal(form.down_payment_cents, 30000); assert.equal(form.general_discount_cents, 123);
  assert.equal(form.items[0].discount_cents, 123); assert.equal(form.items[0].discount_mode, 'amount');
  assert.equal(form.items[0].recurring_cents, 0); assert.equal(form.first_due_date, '2026-09-29');
});
test('payload sends accepted source identity and exact discount, not a rounded percent', () => {
  const form = { ...proposalToOrderForm(fixture()), proposal_id: 44 };
  const payload = orderFinancialPayload(form);
  assert.equal(payload.proposal_id, 44); assert.equal(payload.items[0].discount_cents, 123);
  assert.equal(payload.items[0].discount_percent, undefined); assert.equal(payload.total_cents, undefined);
  assert.equal(payload.snapshot.shipping_in_installments, false); assert.equal(payload.snapshot.has_monthly_fee, false);
});
test('retains billing franchise implementation and validity metadata', () => {
  const form = proposalToOrderForm(fixture()); const s = orderFinancialPayload(form).items[0].snapshot;
  assert.equal(s.billing_model, 'monthly'); assert.equal(s.setup_fee_cents, 500);
  assert.equal(s.included_quantity, 20); assert.equal(s.included_unit, 'ramais');
  assert.equal(s.overage_unit_price_cents, 10); assert.equal(s.activation_days, 2); assert.equal(s.validation_period_days, 7);
});
test('all payment/freight/recurrence choices survive hydration', () => {
  for (const condition of ['cash', 'installments', 'down_payment_installments']) {
    for (const shipping of [false, true]) for (const monthly of [false, true]) {
      const data = fixture(); Object.assign(data.financials, { payment_condition: condition, shipping_in_installments: shipping, has_monthly_fee: monthly });
      const payload = orderFinancialPayload(proposalToOrderForm(data));
      assert.equal(payload.payment_condition, condition); assert.equal(payload.snapshot.shipping_in_installments, shipping);
      assert.equal(payload.snapshot.has_monthly_fee, monthly);
    }
  }
});
test('zero amounts are not replaced with older nonzero fields', () => {
  const data = fixture(); data.down_payment_cents = 999; data.financials.down_payment_cents = 0;
  assert.equal(proposalToOrderForm(data).down_payment_cents, 0);
});
test('manual item percent remains an explicit input to server calculation', () => {
  const form = proposalToOrderForm(fixture()); form.items[0].discount_mode = 'percent'; form.items[0].discount_percent = 7.5;
  const payload = orderFinancialPayload(form); assert.equal(payload.items[0].discount_percent, 7.5);
  assert.equal(payload.items[0].discount_cents, undefined);
});
test('helper introduces no institutional GoPure default', () => {
  assert.doesNotMatch(source, /gopure/i);
});
