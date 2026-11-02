class ProtectJrcHumanAssignmentPolicyEvents < ActiveRecord::Migration[7.1]
  IMMUTABILITY_SQL = <<~SQL.freeze
    CREATE FUNCTION jrc_human_policy_immutable_guard() RETURNS trigger
    LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
    BEGIN
      -- Preserve only the parent-removal actions already defined by the original FKs.
      IF TG_OP = 'DELETE' THEN
        IF pg_trigger_depth() > 1 AND (
          NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = OLD.account_id) OR
          (OLD.inbox_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.inboxes WHERE id = OLD.inbox_id))
        ) THEN
          RETURN OLD;
        END IF;
      ELSIF TG_OP = 'UPDATE' THEN
        IF pg_trigger_depth() > 1 AND OLD.user_id IS NOT NULL AND NEW.user_id IS NULL AND
          (to_jsonb(NEW) - 'user_id') IS NOT DISTINCT FROM (to_jsonb(OLD) - 'user_id') AND
          NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id)
        THEN
          RETURN NEW;
        END IF;
      END IF;
      RAISE EXCEPTION 'Human assignment policy history is append-only' USING ERRCODE = '23514';
    END;
    $$;
    CREATE TRIGGER jrc_human_policy_immutable_rows
      BEFORE UPDATE OR DELETE ON jrc_human_assignment_policy_events
      FOR EACH ROW EXECUTE FUNCTION jrc_human_policy_immutable_guard();
    CREATE TRIGGER jrc_human_policy_immutable_truncate
      BEFORE TRUNCATE ON jrc_human_assignment_policy_events
      FOR EACH STATEMENT EXECUTE FUNCTION jrc_human_policy_immutable_guard();
  SQL
  private_constant :IMMUTABILITY_SQL

  def up
    change_column_null :jrc_human_assignment_policy_events, :inbox_id, true
    add_check_constraint :jrc_human_assignment_policy_events,
                         "inbox_id IS NOT NULL OR (next_policy ->> 'scope') IS NOT DISTINCT FROM 'GLOBAL_ACCOUNT'",
                         name: 'jrc_human_policy_global_account_scope'
    execute IMMUTABILITY_SQL
  end

  def down
    if select_value('SELECT EXISTS (SELECT 1 FROM jrc_human_assignment_policy_events WHERE inbox_id IS NULL)')
      raise ActiveRecord::IrreversibleMigration, 'Account-global audit history cannot be discarded to restore a mandatory inbox'
    end

    execute 'DROP TRIGGER jrc_human_policy_immutable_truncate ON jrc_human_assignment_policy_events'
    execute 'DROP TRIGGER jrc_human_policy_immutable_rows ON jrc_human_assignment_policy_events'
    execute 'DROP FUNCTION jrc_human_policy_immutable_guard()'
    remove_check_constraint :jrc_human_assignment_policy_events, name: 'jrc_human_policy_global_account_scope'
    change_column_null :jrc_human_assignment_policy_events, :inbox_id, false
  end
end
