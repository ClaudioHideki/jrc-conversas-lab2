-- Immutable private rule history; no public controller or execution trigger is introduced by these guards.
-- Account settings/audit retain only revision and a random nonce; the definition digest stays private.

CREATE FUNCTION cc_ending_action_definition_digest(document jsonb) RETURNS text
LANGUAGE sql IMMUTABLE STRICT AS $guard$
  SELECT encode(sha256(convert_to(document::text, 'UTF8')), 'hex')
$guard$;

CREATE FUNCTION cc_ending_action_version_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE source audits%ROWTYPE;
  previous jrc_contact_center_ending_action_versions%ROWTYPE;
  configured jsonb; previous_head jsonb; next_head jsonb; digest_value text;
  captured timestamp without time zone;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending action versions are immutable'; END IF;
  SELECT settings #> '{jrc_contact_center_acw,voice_ending_automations}' INTO configured
    FROM accounts WHERE id = NEW.account_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending action account unavailable'; END IF;
  SELECT * INTO previous FROM jrc_contact_center_ending_action_versions
    WHERE account_id = NEW.account_id ORDER BY revision DESC LIMIT 1;
  IF NEW.revision IS DISTINCT FROM COALESCE(previous.revision, 0) + 1
    OR jsonb_typeof(NEW.private_definition) IS DISTINCT FROM 'object'
    OR NEW.private_definition -> 'version' IS DISTINCT FROM to_jsonb(NEW.revision)
    OR jsonb_typeof(NEW.private_definition -> 'entries') IS DISTINCT FROM 'array'
    OR NEW.head_nonce IS NULL
    OR NEW.head_nonce::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION 'Ending action definition sequence conflict';
  END IF;
  IF jsonb_array_length(NEW.private_definition -> 'entries') > 100
    OR octet_length(NEW.private_definition::text) > 524288 THEN
    RAISE EXCEPTION 'Ending action definition bounds unavailable';
  END IF;
  IF EXISTS (SELECT 1 FROM jrc_contact_center_ending_action_versions
    WHERE account_id = NEW.account_id AND head_nonce = NEW.head_nonce) THEN
    RAISE EXCEPTION 'Ending action definition head already used';
  END IF;
  digest_value = cc_ending_action_definition_digest(NEW.private_definition);
  next_head = jsonb_build_object('version', NEW.revision, 'nonce', NEW.head_nonce);
  IF configured IS DISTINCT FROM next_head THEN RAISE EXCEPTION 'Ending action private definition head mismatch'; END IF;
  IF previous.id IS NOT NULL THEN
    previous_head = jsonb_build_object('version', previous.revision, 'nonce', previous.head_nonce);
  END IF;
  SELECT * INTO source FROM audits WHERE id = NEW.source_audit_id;
  IF NOT FOUND OR source.auditable_type IS DISTINCT FROM 'Account' OR source.auditable_id IS DISTINCT FROM NEW.account_id
    OR source.associated_type IS DISTINCT FROM 'Account' OR source.associated_id IS DISTINCT FROM NEW.account_id
    OR source.action IS DISTINCT FROM 'update' OR source.comment IS DISTINCT FROM 'jrc_contact_center_acw_policy_v1'
    OR source.user_type IS DISTINCT FROM 'User' OR source.user_id IS NULL
    OR source.audited_changes #> '{cc_scope,before,account_id}' IS DISTINCT FROM to_jsonb(NEW.account_id::text)
    OR source.audited_changes #> '{cc_scope,after,account_id}' IS DISTINCT FROM to_jsonb(NEW.account_id::text)
    OR source.audited_changes #> '{attributes,0,voice_ending_automations}' IS DISTINCT FROM previous_head
    OR source.audited_changes #> '{attributes,1,voice_ending_automations}' IS DISTINCT FROM next_head THEN
    RAISE EXCEPTION 'Ending action audit provenance unavailable';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM account_users members JOIN users actors ON actors.id = members.user_id
    WHERE members.account_id = NEW.account_id AND members.user_id = source.user_id AND actors.id = source.user_id) THEN
    RAISE EXCEPTION 'Ending action configuration actor unavailable';
  END IF;
  -- No existing automation is being backfilled. Effective time is the real server capture, never a client/audit-supplied date.
  captured = timezone('UTC', clock_timestamp());
  IF previous.id IS NOT NULL AND captured <= previous.created_at THEN
    RAISE EXCEPTION 'Ending action version clock order unavailable';
  END IF;
  NEW.actor_user_id = source.user_id;
  NEW.actor_user_type = source.user_type;
  NEW.definition_sha256 = digest_value;
  NEW.created_at = captured;
  NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', NEW.account_id, 'revision', NEW.revision,
    'source_audit_id', NEW.source_audit_id, 'actor_user_id', NEW.actor_user_id, 'head_nonce', NEW.head_nonce,
    'definition_sha256', NEW.definition_sha256,
    'created_at', NEW.created_at)::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_version_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_versions FOR EACH ROW EXECUTE FUNCTION cc_ending_action_version_guard();
