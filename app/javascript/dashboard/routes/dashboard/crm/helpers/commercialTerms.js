// No pricing arithmetic here: the server is authoritative for all three stages.
export const proposalToOrderForm = proposal => {
  const terms = proposal.financials || {};
  return {
    customer_name: proposal.customer?.name || '', contact_id: proposal.customer?.id || null,
    deal_id: proposal.deal_id || proposal.deal?.id || null, owner_id: proposal.owner?.id || null,
    payment_condition: terms.payment_condition || proposal.payment_condition || 'cash',
    payment_method: terms.payment_method || proposal.payment_method || proposal.payment?.method || 'boleto',
    installments_count: terms.installments_count || proposal.installments_count || 1,
    down_payment_cents: terms.down_payment_cents ?? proposal.down_payment_cents ?? 0,
    shipping_cents: terms.shipping_cents ?? proposal.shipping_cents ?? 0,
    shipping_mode: terms.shipping_mode || proposal.shipping_mode || 'not_applicable',
    shipping_in_installments: terms.shipping_in_installments ?? proposal.shipping_in_installments ?? true,
    has_monthly_fee: terms.has_monthly_fee ?? proposal.has_monthly_fee ?? true,
    first_due_date: terms.first_due_date || '',
    general_discount_cents: terms.discount_cents ?? proposal.discount_cents ?? 0,
    discount_percent: 0, taxes_percent: 0,
    items: (proposal.items || []).map(item => ({
      product_id: item.product_id, name: item.name_snapshot || item.product?.name || 'Item',
      description: item.description_snapshot || '', quantity: Number(item.quantity || 1),
      unit_cents: Number(item.unit_price_cents || 0), discount_cents: Number(item.discount_cents || 0),
      discount_percent: item.unit_price_cents && item.quantity
        ? Number(item.discount_cents || 0) * 100 / (Number(item.unit_price_cents) * Number(item.quantity)) : 0,
      discount_mode: 'amount', one_time_cents: Number(item.initial_total_cents || item.total_cents || 0),
      recurring_cents: (terms.has_monthly_fee ?? proposal.has_monthly_fee ?? true) ? Number(item.recurring_total_cents || 0) : 0,
      snapshot: { billing_model: item.billing_model || 'one_time', setup_fee_cents: Number(item.setup_fee_cents || 0),
        unit_name: item.unit_name, description: item.description_snapshot || '', included_quantity: item.included_quantity,
        included_unit: item.included_unit, overage_unit_price_cents: item.overage_unit_price_cents,
        activation_days: item.activation_days, validation_period_days: item.validation_period_days,
        implementation_type: 'Assistida', implementation_owner: '', implementation_date: '', status: 'Pendente' },
    })),
  };
};

export const orderFinancialPayload = form => ({
  proposal_id: form.proposal_id || null,
  payment_condition: form.payment_condition, payment_method: form.payment_method,
  down_payment_cents: Number(form.down_payment_cents || 0),
  shipping_cents: Number(form.shipping_cents || 0),
  discount_cents: Number(form.general_discount_cents || 0),
  installments_count: Number(form.installments_count || 1),
  items: form.items.map(item => ({ product_id: item.product_id, name: item.name, quantity: item.quantity,
    unit_cents: item.unit_cents, snapshot: item.snapshot,
    ...(item.discount_mode === 'amount' ? { discount_cents: item.discount_cents } : { discount_percent: item.discount_percent || 0 }),
  })),
  snapshot: {
    ...(form.general_discount_cents == null ? { discount_percent: Number(form.discount_percent || 0) } : {}),
    taxes_percent: Number(form.taxes_percent || 0), first_due_date: form.first_due_date || form.order_date,
    shipping_mode: form.shipping_mode, shipping_in_installments: form.shipping_in_installments,
    has_monthly_fee: form.has_monthly_fee,
  },
});
