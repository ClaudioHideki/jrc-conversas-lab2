-- Additive typed ending history guards. Installation never activates work.
-- Metadata only. Every actual attempt must still enter OriginalActorContext
-- and the existing destination services under current native permissions.
-- The published Project-only success/attempt functions remain unchanged.
CREATE FUNCTION cc_ending_destination_context(
  source_account_id bigint, source_origin_id bigint, source_readiness_id bigint,
  source_rule_code text, source_destination_kind text
) RETURNS jsonb
LANGUAGE plpgsql AS $context$
DECLARE origin jrc_contact_center_ending_action_origins%ROWTYPE;
  ready jrc_contact_center_ending_action_readinesses%ROWTYPE;
  version jrc_contact_center_ending_action_versions%ROWTYPE;
  confirmation jrc_contact_center_ending_reason_confirmations%ROWTYPE;
  completion jrc_contact_center_ending_action_completions%ROWTYPE;
  rule jsonb; action jsonb; count_matches integer;
  operation_name text; trigger_kind text; trigger_id bigint;
  triggered_at timestamp without time zone;
BEGIN
  IF source_rule_code IS NULL OR length(source_rule_code) NOT BETWEEN 1 AND 100
    OR source_destination_kind IS NULL
    OR source_destination_kind NOT IN ('project_task', 'crm', 'service_desk') THEN
    RAISE EXCEPTION 'Typed ending destination identity unavailable';
  END IF;
  -- Same native account mutex as the existing worker. This never grants access.
  PERFORM 1 FROM accounts WHERE id = source_account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending destination account unavailable'; END IF;
  SELECT * INTO origin FROM jrc_contact_center_ending_action_origins
    WHERE id = source_origin_id AND account_id = source_account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending destination original unavailable'; END IF;
  SELECT * INTO ready FROM jrc_contact_center_ending_action_readinesses
    WHERE id = source_readiness_id AND account_id = source_account_id;
  IF NOT FOUND OR ready.rule_code IS DISTINCT FROM source_rule_code
    OR NOT cc_ending_action_readiness_matches(ready.id, origin.id) THEN
    RAISE EXCEPTION 'Typed ending destination prospective readiness unavailable';
  END IF;
  SELECT * INTO version FROM jrc_contact_center_ending_action_versions
    WHERE id = origin.version_id AND account_id = origin.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending destination version unavailable'; END IF;
  SELECT count(*) INTO count_matches FROM jsonb_array_elements(version.private_definition -> 'entries') entry
    WHERE entry ->> 'code' = source_rule_code;
  IF count_matches <> 1 THEN RAISE EXCEPTION 'Typed ending destination rule ambiguous or unavailable'; END IF;
  SELECT entry INTO rule FROM jsonb_array_elements(version.private_definition -> 'entries') entry
    WHERE entry ->> 'code' = source_rule_code;
  IF rule -> 'destination_schema_version' IS DISTINCT FROM '2'::jsonb
    OR rule -> 'active' IS DISTINCT FROM 'true'::jsonb
    OR rule ->> 'execution_mode' IS NULL
    OR rule ->> 'execution_mode' NOT IN ('automatic', 'agent_confirmation') THEN
    RAISE EXCEPTION 'Explicit new typed ending rule required';
  END IF;
  -- An intervening deactivation blocks old pending work permanently, even
  -- after reactivation. The original immutable version remains the parameters.
  IF EXISTS (SELECT 1 FROM jrc_contact_center_ending_action_versions later
    WHERE later.account_id = origin.account_id AND later.revision > version.revision
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(later.private_definition -> 'entries') entry
        WHERE entry ->> 'code' = source_rule_code AND entry -> 'active' = 'true'::jsonb)) THEN
    RAISE EXCEPTION 'Typed ending destination permanently blocked by deactivation';
  END IF;
  SELECT count(*) INTO count_matches FROM jsonb_array_elements(rule -> 'actions') entry
    WHERE entry ->> 'kind' = source_destination_kind;
  IF count_matches <> 1 THEN RAISE EXCEPTION 'Typed ending destination ambiguous or unavailable'; END IF;
  SELECT entry INTO action FROM jsonb_array_elements(rule -> 'actions') entry
    WHERE entry ->> 'kind' = source_destination_kind;
  IF jsonb_typeof(action -> 'parameters') IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'Typed ending destination parameters unavailable';
  END IF;
  operation_name = action #>> '{parameters,operation}';
  IF NOT ((action -> 'parameters') ? 'operation') THEN
    operation_name = CASE source_destination_kind
      WHEN 'project_task' THEN 'create_task'
      WHEN 'crm' THEN 'create_lead'
      WHEN 'service_desk' THEN 'create_ticket'
    END;
  END IF;
  IF operation_name IS NULL OR NOT (
    (source_destination_kind = 'project_task' AND operation_name = 'create_task')
    OR (source_destination_kind = 'crm' AND operation_name IN ('create_lead', 'create_activity'))
    OR (source_destination_kind = 'service_desk' AND operation_name IN ('create_ticket', 'update_ticket'))
  ) THEN RAISE EXCEPTION 'Typed ending destination operation unavailable'; END IF;

  IF rule ->> 'timing' = 'call_end' THEN
    SELECT * INTO confirmation FROM jrc_contact_center_ending_reason_confirmations
      WHERE account_id = origin.account_id AND source_qualification_id = origin.source_qualification_id
        AND actor_account_user_id = origin.actor_account_user_id AND actor_user_id = origin.actor_user_id
        AND catalogue_id = origin.ending_reason_catalog_id AND reason_code = rule ->> 'reason_code';
    IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending classification must be explicitly confirmed'; END IF;
    trigger_kind = 'ending_reason_confirmation';
    trigger_id = confirmation.id;
    triggered_at = greatest(origin.created_at, confirmation.created_at);
  ELSIF rule ->> 'timing' = 'acw_completed' THEN
    SELECT * INTO completion FROM jrc_contact_center_ending_action_completions
      WHERE account_id = origin.account_id AND origin_id = origin.id AND reason_code = rule ->> 'reason_code';
    IF NOT FOUND OR NOT cc_ending_action_completion_matches(origin.id, origin.source_qualification_id) THEN
      RAISE EXCEPTION 'Typed ending actual native ACW completion required';
    END IF;
    IF jsonb_array_length(rule #> '{conditions,outcome_codes}') > 0
      AND NOT ((rule #> '{conditions,outcome_codes}') ? completion.outcome_code) THEN
      RAISE EXCEPTION 'Typed ending completion condition mismatch';
    END IF;
    trigger_kind = 'ending_action_completion';
    trigger_id = completion.id;
    triggered_at = completion.completed_at;
  ELSE RAISE EXCEPTION 'Typed ending native trigger unavailable';
  END IF;
  RETURN jsonb_build_object(
    'account_id', origin.account_id, 'origin_id', origin.id, 'version_id', origin.version_id,
    'readiness_id', ready.id, 'rule_code', source_rule_code, 'rule_sha256', ready.rule_sha256,
    'actor_account_user_id', origin.actor_account_user_id, 'actor_user_id', origin.actor_user_id,
    'destination_kind', source_destination_kind, 'operation', operation_name,
    'execution_mode', rule ->> 'execution_mode', 'trigger_kind', trigger_kind,
    'trigger_id', trigger_id, 'triggered_at', triggered_at, 'source_timezone', ready.source_timezone
  );
END $context$;

CREATE FUNCTION cc_ending_destination_consent_guard() RETURNS trigger
LANGUAGE plpgsql AS $consent$
DECLARE metadata jsonb;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Typed ending action consent is immutable'; END IF;
  IF NEW.version_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL OR NEW.operation IS NOT NULL
    OR NEW.rule_sha256 IS NOT NULL OR NEW.trigger_kind IS NOT NULL OR NEW.trigger_id IS NOT NULL
    OR NEW.triggered_at IS NOT NULL OR NEW.created_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'Typed ending action consent evidence is server generated';
  END IF;
  metadata = cc_ending_destination_context(NEW.account_id, NEW.origin_id, NEW.readiness_id, NEW.rule_code, NEW.destination_kind);
  IF metadata ->> 'execution_mode' IS DISTINCT FROM 'agent_confirmation'
    OR NEW.actor_account_user_id IS DISTINCT FROM (metadata ->> 'actor_account_user_id')::bigint THEN
    RAISE EXCEPTION 'Typed ending explicit original-agent action consent required';
  END IF;
  IF EXISTS (SELECT 1 FROM jrc_contact_center_ending_destination_executions execution
    WHERE execution.account_id = NEW.account_id AND execution.origin_id = NEW.origin_id
      AND execution.rule_code = NEW.rule_code AND execution.destination_kind = NEW.destination_kind) THEN
    RAISE EXCEPTION 'Typed ending action already succeeded';
  END IF;
  -- Only server-derived metadata replaces generated fields. This record does
  -- not complete ACW, confirm a classification or authorize any native target.
  NEW = jsonb_populate_record(NEW, metadata);
  NEW.created_at = timezone('UTC', clock_timestamp());
  IF NEW.created_at < NEW.triggered_at THEN RAISE EXCEPTION 'Typed ending consent clock order unavailable'; END IF;
  NEW.integrity_sha256 = encode(sha256(convert_to((to_jsonb(NEW) - 'integrity_sha256')::text, 'UTF8')), 'hex');
  RETURN NEW;
END $consent$;

CREATE FUNCTION cc_ending_destination_attempt_guard() RETURNS trigger
LANGUAGE plpgsql AS $attempt$
DECLARE metadata jsonb;
  consent jrc_contact_center_ending_destination_consents%ROWTYPE;
  previous jrc_contact_center_ending_destination_attempts%ROWTYPE;
  previous_result jrc_contact_center_ending_destination_outcomes%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Typed ending destination attempts are immutable'; END IF;
  IF NEW.version_id IS NOT NULL OR NEW.actor_account_user_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL
    OR NEW.operation IS NOT NULL OR NEW.rule_sha256 IS NOT NULL OR NEW.effect_key IS NOT NULL
    OR NEW.trigger_kind IS NOT NULL OR NEW.trigger_id IS NOT NULL OR NEW.triggered_at IS NOT NULL
    OR NEW.created_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'Typed ending destination attempt evidence is server generated';
  END IF;
  metadata = cc_ending_destination_context(NEW.account_id, NEW.origin_id, NEW.readiness_id, NEW.rule_code, NEW.destination_kind);
  IF EXISTS (SELECT 1 FROM jrc_contact_center_ending_destination_executions execution
    WHERE execution.account_id = NEW.account_id AND execution.origin_id = NEW.origin_id
      AND execution.rule_code = NEW.rule_code AND execution.destination_kind = NEW.destination_kind) THEN
    RAISE EXCEPTION 'Typed ending destination already succeeded';
  END IF;
  IF metadata ->> 'execution_mode' = 'agent_confirmation' THEN
    SELECT * INTO consent FROM jrc_contact_center_ending_destination_consents
      WHERE id = NEW.consent_id AND account_id = NEW.account_id;
    IF NOT FOUND OR consent.origin_id IS DISTINCT FROM NEW.origin_id OR consent.readiness_id IS DISTINCT FROM NEW.readiness_id
      OR consent.rule_code IS DISTINCT FROM NEW.rule_code OR consent.destination_kind IS DISTINCT FROM NEW.destination_kind
      OR consent.operation IS DISTINCT FROM metadata ->> 'operation'
      OR consent.request_key IS DISTINCT FROM NEW.request_key
      OR consent.actor_account_user_id IS DISTINCT FROM (metadata ->> 'actor_account_user_id')::bigint
      OR consent.actor_user_id IS DISTINCT FROM (metadata ->> 'actor_user_id')::bigint
      OR consent.version_id IS DISTINCT FROM (metadata ->> 'version_id')::bigint
      OR consent.rule_sha256 IS DISTINCT FROM metadata ->> 'rule_sha256'
      OR consent.trigger_kind IS DISTINCT FROM metadata ->> 'trigger_kind'
      OR consent.trigger_id IS DISTINCT FROM (metadata ->> 'trigger_id')::bigint
      OR consent.triggered_at IS DISTINCT FROM (metadata ->> 'triggered_at')::timestamp THEN
      RAISE EXCEPTION 'Exact typed ending action consent required';
    END IF;
  ELSIF NEW.consent_id IS NOT NULL THEN
    RAISE EXCEPTION 'Automatic ending mode cannot reuse manual action consent';
  END IF;
  SELECT * INTO previous FROM jrc_contact_center_ending_destination_attempts
    WHERE account_id = NEW.account_id AND origin_id = NEW.origin_id
      AND rule_code = NEW.rule_code AND destination_kind = NEW.destination_kind ORDER BY id DESC LIMIT 1;
  IF previous.id IS NULL THEN
    IF NEW.retry_of_id IS NOT NULL OR NEW.retry_requested_by_account_user_id IS NOT NULL THEN
      RAISE EXCEPTION 'Typed ending first attempt cannot invent retry ancestry';
    END IF;
    NEW.effect_key = NEW.request_key;
  ELSE
    SELECT * INTO previous_result FROM jrc_contact_center_ending_destination_outcomes
      WHERE account_id = NEW.account_id AND attempt_id = previous.id;
    IF NOT FOUND OR previous_result.outcome NOT IN ('failed', 'blocked')
      OR NEW.retry_of_id IS DISTINCT FROM previous.id OR previous.readiness_id IS DISTINCT FROM NEW.readiness_id
      OR NEW.retry_requested_by_account_user_id IS DISTINCT FROM (metadata ->> 'actor_account_user_id')::bigint
      OR previous.operation IS DISTINCT FROM metadata ->> 'operation' THEN
      RAISE EXCEPTION 'Typed ending retry requires exact unsuccessful predecessor and original-agent review';
    END IF;
    NEW.effect_key = previous.effect_key;
  END IF;
  NEW = jsonb_populate_record(NEW, metadata);
  NEW.created_at = timezone('UTC', clock_timestamp());
  IF NEW.created_at < NEW.triggered_at OR (consent.id IS NOT NULL AND NEW.created_at < consent.created_at) THEN
    RAISE EXCEPTION 'Typed ending attempt clock order unavailable';
  END IF;
  NEW.integrity_sha256 = encode(sha256(convert_to((to_jsonb(NEW) - 'integrity_sha256')::text, 'UTF8')), 'hex');
  RETURN NEW;
END $attempt$;

CREATE FUNCTION cc_ending_destination_outcome_guard() RETURNS trigger
LANGUAGE plpgsql AS $outcome$
DECLARE attempt jrc_contact_center_ending_destination_attempts%ROWTYPE;
  execution jrc_contact_center_ending_destination_executions%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Typed ending destination outcomes are immutable'; END IF;
  IF NEW.created_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'Typed ending outcome time and digest are server generated';
  END IF;
  -- Failed/blocked evidence remains appendable after source rights are revoked
  -- or a rule is disabled. It records a refusal, never authorizes an effect.
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending outcome account unavailable'; END IF;
  SELECT * INTO attempt FROM jrc_contact_center_ending_destination_attempts
    WHERE id = NEW.attempt_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending outcome attempt unavailable'; END IF;
  IF NEW.outcome = 'succeeded' THEN
    SELECT * INTO execution FROM jrc_contact_center_ending_destination_executions
      WHERE id = NEW.execution_id AND account_id = NEW.account_id;
    IF NOT FOUND OR execution.attempt_id IS DISTINCT FROM attempt.id
      OR execution.origin_id IS DISTINCT FROM attempt.origin_id OR execution.readiness_id IS DISTINCT FROM attempt.readiness_id
      OR execution.rule_code IS DISTINCT FROM attempt.rule_code OR execution.destination_kind IS DISTINCT FROM attempt.destination_kind
      OR execution.operation IS DISTINCT FROM attempt.operation OR execution.effect_key IS DISTINCT FROM attempt.effect_key THEN
      RAISE EXCEPTION 'Typed ending outcome native success identity mismatch';
    END IF;
  ELSIF NEW.execution_id IS NOT NULL THEN
    RAISE EXCEPTION 'Typed ending failure cannot claim a native success';
  END IF;
  NEW.created_at = timezone('UTC', clock_timestamp());
  NEW.integrity_sha256 = encode(sha256(convert_to((to_jsonb(NEW) - 'integrity_sha256')::text, 'UTF8')), 'hex');
  RETURN NEW;
END $outcome$;

CREATE FUNCTION cc_ending_destination_execution_guard() RETURNS trigger
LANGUAGE plpgsql AS $execution$
DECLARE attempt jrc_contact_center_ending_destination_attempts%ROWTYPE;
  origin jrc_contact_center_ending_action_origins%ROWTYPE;
  saved_contact contacts%ROWTYPE;
  activity jrc_crm_activities%ROWTYPE;
  ticket jrc_service_desk_tickets%ROWTYPE;
  metadata jsonb; action jsonb;
  mapped_unit_id bigint; expected_version bigint;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Typed ending native successes are immutable'; END IF;
  IF NEW.origin_id IS NOT NULL OR NEW.readiness_id IS NOT NULL OR NEW.version_id IS NOT NULL
    OR NEW.actor_account_user_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL OR NEW.rule_code IS NOT NULL
    OR NEW.destination_kind IS NOT NULL OR NEW.operation IS NOT NULL OR NEW.rule_sha256 IS NOT NULL
    OR NEW.request_key IS NOT NULL OR NEW.effect_key IS NOT NULL OR NEW.target_type IS NOT NULL
    OR NEW.native_audit_id IS NOT NULL OR NEW.native_version IS NOT NULL
    OR NEW.trigger_kind IS NOT NULL OR NEW.trigger_id IS NOT NULL OR NEW.triggered_at IS NOT NULL
    OR NEW.created_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'Typed ending native success evidence is server generated';
  END IF;
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native success account unavailable'; END IF;
  SELECT * INTO attempt FROM jrc_contact_center_ending_destination_attempts
    WHERE id = NEW.attempt_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native success attempt unavailable'; END IF;
  IF EXISTS (SELECT 1 FROM jrc_contact_center_ending_destination_outcomes
    WHERE account_id = NEW.account_id AND attempt_id = attempt.id) THEN
    RAISE EXCEPTION 'A terminal typed ending attempt cannot acquire another effect';
  END IF;
  metadata = cc_ending_destination_context(attempt.account_id, attempt.origin_id, attempt.readiness_id,
                                          attempt.rule_code, attempt.destination_kind);
  IF attempt.version_id IS DISTINCT FROM (metadata ->> 'version_id')::bigint
    OR attempt.actor_account_user_id IS DISTINCT FROM (metadata ->> 'actor_account_user_id')::bigint
    OR attempt.actor_user_id IS DISTINCT FROM (metadata ->> 'actor_user_id')::bigint
    OR attempt.operation IS DISTINCT FROM metadata ->> 'operation'
    OR attempt.rule_sha256 IS DISTINCT FROM metadata ->> 'rule_sha256'
    OR attempt.trigger_kind IS DISTINCT FROM metadata ->> 'trigger_kind'
    OR attempt.trigger_id IS DISTINCT FROM (metadata ->> 'trigger_id')::bigint
    OR attempt.triggered_at IS DISTINCT FROM (metadata ->> 'triggered_at')::timestamp THEN
    RAISE EXCEPTION 'Typed ending original attempt identity mismatch';
  END IF;
  NEW = jsonb_populate_record(NEW, metadata);
  NEW.request_key = attempt.request_key;
  NEW.effect_key = attempt.effect_key;
  SELECT * INTO origin FROM jrc_contact_center_ending_action_origins
    WHERE id = attempt.origin_id AND account_id = attempt.account_id;
  SELECT entry INTO action FROM jrc_contact_center_ending_action_versions version
    CROSS JOIN LATERAL jsonb_array_elements(version.private_definition -> 'entries') rule
    CROSS JOIN LATERAL jsonb_array_elements(rule -> 'actions') entry
    WHERE version.id = origin.version_id AND version.account_id = origin.account_id
      AND rule ->> 'code' = attempt.rule_code AND entry ->> 'kind' = attempt.destination_kind;

  IF NEW.operation = 'create_task' THEN
    PERFORM 1 FROM jrc_projects_tasks WHERE id = NEW.target_id AND account_id = NEW.account_id
      AND project_id::text = action #>> '{parameters,project_id}' AND created_by_id = NEW.actor_user_id
      AND created_at >= attempt.created_at;
    IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native Project task identity mismatch'; END IF;
    SELECT audit.id INTO NEW.native_audit_id FROM jrc_projects_audit_events audit
      WHERE audit.account_id = NEW.account_id AND audit.actor_id = NEW.actor_user_id AND audit.action = 'projects.task.created'
        AND audit.auditable_type = 'JrcProjects::Task' AND audit.auditable_id = NEW.target_id
        AND audit.correlation_id = attempt.effect_key::text AND audit.created_at >= attempt.created_at
      ORDER BY audit.id DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native Project task audit required'; END IF;
    NEW.target_type = 'JrcProjects::Task';
  ELSE
    SELECT * INTO saved_contact FROM contacts WHERE account_id = NEW.account_id
      AND id::text = origin.private_origin_evidence ->> 'contact_id';
    IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending explicit original customer required'; END IF;
    IF NEW.operation = 'create_lead' THEN
      -- Native ContactLeadService may legitimately return an already visible
      -- Lead. This receipt does not claim that an existing Lead was recreated.
      PERFORM 1 FROM jrc_crm_leads WHERE id = NEW.target_id AND account_id = NEW.account_id AND contact_id = saved_contact.id;
      IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native CRM Lead identity mismatch'; END IF;
      NEW.target_type = 'JrcCrm::Lead';
    ELSIF NEW.operation = 'create_activity' THEN
      SELECT * INTO activity FROM jrc_crm_activities WHERE id = NEW.target_id AND account_id = NEW.account_id
        AND contact_id = saved_contact.id AND user_id = NEW.actor_user_id AND status = 'completed'
        AND completed_at = NEW.triggered_at AND due_at = NEW.triggered_at AND created_at >= attempt.created_at;
      IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native CRM activity identity mismatch'; END IF;
      SELECT id INTO NEW.native_audit_id FROM jrc_crm_audit_events WHERE account_id = NEW.account_id
        AND resource_type = 'JrcCrm::Activity' AND resource_id = activity.id AND event_type = 'activity_created'
        AND actor_type = 'User' AND actor_id = NEW.actor_user_id AND created_at >= attempt.created_at ORDER BY id DESC LIMIT 1;
      IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native CRM activity audit required'; END IF;
      NEW.target_type = 'JrcCrm::Activity';
    ELSIF NEW.operation IN ('create_ticket', 'update_ticket') THEN
      SELECT * INTO ticket FROM jrc_service_desk_tickets WHERE id = NEW.target_id AND account_id = NEW.account_id
        AND requester_id = saved_contact.id AND company_id IS NOT DISTINCT FROM saved_contact.company_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native Service Desk customer mismatch'; END IF;
      SELECT (settings ->> 'service_desk_unit_id')::bigint INTO mapped_unit_id FROM jrc_crm_business_units
        WHERE id = origin.business_unit_id AND account_id = origin.account_id AND company_id = origin.issuer_company_id AND active;
      IF NOT FOUND OR mapped_unit_id IS DISTINCT FROM ticket.unit_id THEN
        RAISE EXCEPTION 'Typed ending native Service Desk source mapping unavailable';
      END IF;
      IF NEW.operation = 'create_ticket' THEN
        IF ticket.unit_id::text IS DISTINCT FROM action #>> '{parameters,unit_id}'
          OR ticket.idempotency_key IS DISTINCT FROM attempt.effect_key::text OR ticket.created_at < attempt.created_at THEN
          RAISE EXCEPTION 'Typed ending native Service Desk creation identity mismatch';
        END IF;
        SELECT event.id INTO NEW.native_audit_id FROM jrc_service_desk_ticket_events event
          JOIN jrc_service_desk_unit_memberships member ON member.id = event.actor_membership_id
            AND member.account_id = event.account_id AND member.unit_id = event.unit_id
          WHERE event.account_id = NEW.account_id AND event.ticket_id = ticket.id AND event.unit_id = ticket.unit_id
            AND event.event_type = 'ticket_created' AND event.created_at >= attempt.created_at
            AND member.account_user_id = NEW.actor_account_user_id AND member.active AND NOT member.administrative_actor
            AND ticket.created_by_membership_id = member.id ORDER BY event.id DESC LIMIT 1;
        IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native Service Desk creation audit required'; END IF;
        PERFORM 1 FROM jrc_service_desk_ticket_events event WHERE event.account_id = NEW.account_id
          AND event.unit_id = ticket.unit_id AND event.ticket_id = ticket.id AND event.event_type = 'creation_context_recorded'
          AND event.actor_membership_id = ticket.created_by_membership_id AND event.created_at >= attempt.created_at;
        IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native Service Desk creation context required'; END IF;
      ELSE
        -- This is the existing strict invocation form. Operational activation
        -- must address its transient version separately; never silently rebase.
        expected_version = (action #>> '{parameters,parameters,expected_lock_version}')::bigint;
        IF ticket.id::text IS DISTINCT FROM action #>> '{parameters,parameters,ticket_id}'
          OR expected_version IS NULL OR ticket.lock_version < expected_version THEN
          RAISE EXCEPTION 'Typed ending native Service Desk update identity mismatch';
        END IF;
        IF ticket.lock_version > expected_version THEN
          SELECT event.id INTO NEW.native_audit_id FROM jrc_service_desk_ticket_events event
            JOIN jrc_service_desk_unit_memberships member ON member.id = event.actor_membership_id
              AND member.account_id = event.account_id AND member.unit_id = event.unit_id
            WHERE event.account_id = NEW.account_id AND event.ticket_id = ticket.id AND event.unit_id = ticket.unit_id
              AND event.event_type = 'ticket_updated' AND event.created_at >= attempt.created_at
              AND member.account_user_id = NEW.actor_account_user_id AND member.active AND NOT member.administrative_actor
            ORDER BY event.id DESC LIMIT 1;
          IF NOT FOUND THEN RAISE EXCEPTION 'Typed ending native Service Desk update audit required'; END IF;
        END IF;
      END IF;
      NEW.native_version = ticket.lock_version;
      NEW.target_type = 'JrcServiceDesk::Ticket';
    ELSE RAISE EXCEPTION 'Typed ending native destination operation unavailable';
    END IF;
  END IF;
  NEW.created_at = timezone('UTC', clock_timestamp());
  IF NEW.created_at < attempt.created_at THEN RAISE EXCEPTION 'Typed ending native success clock order unavailable'; END IF;
  NEW.integrity_sha256 = encode(sha256(convert_to((to_jsonb(NEW) - 'integrity_sha256')::text, 'UTF8')), 'hex');
  RETURN NEW;
END $execution$;

CREATE TRIGGER cc_typed_consent_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_destination_consents FOR EACH ROW EXECUTE FUNCTION cc_ending_destination_consent_guard();
CREATE TRIGGER cc_typed_attempt_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_destination_attempts FOR EACH ROW EXECUTE FUNCTION cc_ending_destination_attempt_guard();
CREATE TRIGGER cc_typed_execution_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_destination_executions FOR EACH ROW EXECUTE FUNCTION cc_ending_destination_execution_guard();
CREATE TRIGGER cc_typed_outcome_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_destination_outcomes FOR EACH ROW EXECUTE FUNCTION cc_ending_destination_outcome_guard();
