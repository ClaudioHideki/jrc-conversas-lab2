CREATE OR REPLACE FUNCTION jrc_contract_delivery_source_fence()
RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE
  legal_columns text[] := ARRAY[
    'account_id', 'contract_number', 'sales_order_id', 'contract_template_id', 'business_unit_id',
    'contract_type', 'starts_on', 'ends_on', 'term_months', 'renewal_type', 'adjustment_index',
    'monthly_cents', 'one_time_cents', 'payment_condition', 'due_day', 'auto_renew',
    'renewal_notice_days', 'renewal_term_months', 'content_override', 'notes', 'contact_id', 'owner_id'
  ];
BEGIN
  IF ((SELECT jsonb_object_agg(key, value) FROM jsonb_each(to_jsonb(NEW)) WHERE key = ANY(legal_columns))
      IS DISTINCT FROM
      (SELECT jsonb_object_agg(key, value) FROM jsonb_each(to_jsonb(OLD)) WHERE key = ANY(legal_columns))
      OR NEW.lifecycle_metadata->'financials' IS DISTINCT FROM OLD.lifecycle_metadata->'financials'
      OR NEW.lifecycle_metadata->'addenda' IS DISTINCT FROM OLD.lifecycle_metadata->'addenda')
     AND EXISTS (
       SELECT 1 FROM jrc_backoffice_signature_deliveries d
       WHERE d.account_id = OLD.account_id AND d.contract_id = OLD.id
       AND NOT EXISTS (
         SELECT 1 FROM jrc_backoffice_signature_delivery_events e
         WHERE e.account_id = d.account_id AND e.delivery_id = d.id
         AND e.kind IN ('send_rejected', 'sender_blocked', 'canceled_before_send', 'envelope_canceled', 'envelope_declined')
       )
     ) THEN
    RAISE EXCEPTION 'signature_delivery_source_locked' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END
$body$;

CREATE TRIGGER jrc_contract_delivery_source_fence
BEFORE UPDATE ON jrc_crm_contracts
FOR EACH ROW EXECUTE FUNCTION jrc_contract_delivery_source_fence();
