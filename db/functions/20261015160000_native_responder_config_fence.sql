CREATE OR REPLACE FUNCTION jrc_native_responder_config_fence() RETURNS trigger
LANGUAGE plpgsql AS $JRC_NATIVE_FENCE$
DECLARE
  target_bot bigint;
  target_account bigint;
  target_inbox bigint;
  locked_scope record;
BEGIN
  IF TG_TABLE_NAME = 'agent_bots' THEN
    IF TG_OP = 'UPDATE' AND NEW.outgoing_url IS NOT DISTINCT FROM OLD.outgoing_url
       AND NEW.secret IS NOT DISTINCT FROM OLD.secret AND NEW.bot_type IS NOT DISTINCT FROM OLD.bot_type THEN
      RETURN NEW;
    END IF;
    target_bot := OLD.id;
    FOR locked_scope IN
      SELECT s.* FROM jrc_flow_ownership_scopes s
      WHERE
        (EXISTS(SELECT 1 FROM agent_bot_inboxes b WHERE b.agent_bot_id=target_bot AND b.account_id=s.account_id AND b.inbox_id=s.inbox_id)
         OR EXISTS(SELECT 1 FROM conversations c WHERE c.assignee_agent_bot_id=target_bot AND c.account_id=s.account_id AND c.inbox_id=s.inbox_id))
      ORDER BY s.scope_key FOR UPDATE
    LOOP
      IF locked_scope.state = 'FENCED' THEN
        RAISE EXCEPTION 'JRC_NATIVE_INBOX_FENCED' USING ERRCODE='23514';
      END IF;
    END LOOP;
  ELSIF TG_TABLE_NAME = 'agent_bot_inboxes' THEN
    IF TG_OP = 'UPDATE' AND NEW.agent_bot_id IS NOT DISTINCT FROM OLD.agent_bot_id
       AND NEW.inbox_id IS NOT DISTINCT FROM OLD.inbox_id AND NEW.account_id IS NOT DISTINCT FROM OLD.account_id
       AND NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
    FOR locked_scope IN
      SELECT s.* FROM jrc_flow_ownership_scopes s
       WHERE ((TG_OP<>'DELETE' AND s.account_id=NEW.account_id AND s.inbox_id=NEW.inbox_id)
            OR (TG_OP<>'INSERT' AND s.account_id=OLD.account_id AND s.inbox_id=OLD.inbox_id))
      ORDER BY s.scope_key FOR UPDATE
    LOOP
      IF locked_scope.state = 'FENCED' THEN
        RAISE EXCEPTION 'JRC_NATIVE_INBOX_FENCED' USING ERRCODE='23514';
      END IF;
    END LOOP;
  ELSIF TG_TABLE_NAME = 'conversations' THEN
    IF NEW.assignee_agent_bot_id IS NULL THEN RETURN NEW; END IF;
    IF TG_OP='UPDATE' AND NEW.assignee_agent_bot_id IS NOT DISTINCT FROM OLD.assignee_agent_bot_id
       AND NEW.account_id IS NOT DISTINCT FROM OLD.account_id AND NEW.inbox_id IS NOT DISTINCT FROM OLD.inbox_id THEN RETURN NEW; END IF;
    FOR locked_scope IN SELECT s.* FROM jrc_flow_ownership_scopes s
      WHERE s.account_id=NEW.account_id AND s.inbox_id=NEW.inbox_id ORDER BY s.scope_key FOR SHARE
    LOOP
      IF locked_scope.state='FENCED' AND NOT EXISTS(SELECT 1 FROM jrc_flow_ownership_epochs e JOIN agent_bots b ON b.id=e.broker_agent_bot_id
                    WHERE e.id=locked_scope.current_epoch_id AND e.scope_id=locked_scope.id AND e.state IN('FENCED','DRAINED')
                      AND e.broker_agent_bot_id=NEW.assignee_agent_bot_id AND e.broker_agent_bot_callback=b.outgoing_url) THEN
        RAISE EXCEPTION 'JRC_NATIVE_INBOX_FENCED' USING ERRCODE='23514';
      END IF;
    END LOOP;
  ELSIF TG_TABLE_NAME = 'inboxes' THEN
    IF NOT NEW.greeting_enabled AND NOT NEW.enable_auto_assignment THEN RETURN NEW; END IF;
    IF TG_OP='UPDATE' AND NEW.greeting_enabled IS NOT DISTINCT FROM OLD.greeting_enabled
       AND NEW.enable_auto_assignment IS NOT DISTINCT FROM OLD.enable_auto_assignment THEN RETURN NEW; END IF;
    FOR locked_scope IN SELECT s.* FROM jrc_flow_ownership_scopes s
      WHERE s.account_id=NEW.account_id AND s.inbox_id=NEW.id ORDER BY s.scope_key FOR UPDATE
    LOOP
      IF locked_scope.state = 'FENCED' THEN
        RAISE EXCEPTION 'JRC_NATIVE_INBOX_FENCED' USING ERRCODE='23514';
      END IF;
    END LOOP;
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$JRC_NATIVE_FENCE$;
