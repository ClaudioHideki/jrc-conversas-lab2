# frozen_string_literal: true

class CreateContactCenterDeferredPauseRequests < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_deferred_pause_requests

  def up
    return verify_existing! if table_exists?(TABLE)

    create_table TABLE do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :account_user_id, :actor_user_id, null: false
      t.uuid :request_id, null: false
      t.string :request_digest, :catalog_revision, limit: 64, null: false
      t.string :reason_code, limit: 100, null: false
      t.string :reason_label, limit: 255, null: false
      t.bigint :queue_id
      t.string :justification, limit: 1000, null: false, default: ''
      t.string :state, limit: 16, null: false
      t.string :failure_code, limit: 64
      t.datetime :finished_at
      t.timestamps
    end
    constrain_requests
    execute immutable_request_sql
    change_table_comment TABLE, schema_receipt
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Deferred pause history requires a separately reviewed rollback'
  end

  private

  def constrain_requests
    add_foreign_key TABLE, :account_users, column: [:account_user_id, :account_id], primary_key: [:id, :account_id],
                                         on_delete: :cascade, name: 'cc_deferred_pause_member_account_fk'
    add_index TABLE, [:account_id, :request_id], unique: true, name: 'cc_deferred_pause_request_key'
    add_index TABLE, [:account_id, :account_user_id, :id], name: 'cc_deferred_pause_member_key'
    add_index TABLE, [:account_id, :account_user_id], unique: true,
                                                    where: "state::text IN ('pending'::text, 'blocked'::text)", name: 'cc_deferred_pause_active_key'
    add_check_constraint TABLE, "state::text IN ('pending'::text, 'blocked'::text, 'applied'::text, 'cancelled'::text)",
                         name: 'cc_deferred_pause_state'
    add_check_constraint TABLE, "request_digest ~ '^[0-9a-f]{64}$' AND catalog_revision ~ '^[0-9a-f]{64}$' " \
                               "AND btrim(reason_code) <> '' AND btrim(reason_label) <> ''", name: 'cc_deferred_pause_identity'
    add_check_constraint TABLE, "(state::text IN ('pending'::text, 'blocked'::text)) = (finished_at IS NULL) " \
                               "AND ((state::text = 'blocked'::text) = (failure_code IS NOT NULL))", name: 'cc_deferred_pause_terminal'
    add_check_constraint TABLE, "failure_code IS NULL OR failure_code::text IN ('access_revoked'::text, 'pause_catalog_changed'::text, " \
                               "'queue_membership_missing'::text, 'pause_request_review_required'::text)", name: 'cc_deferred_pause_failure'
  end

  def immutable_request_sql
    <<~SQL.squish
      CREATE FUNCTION cc_deferred_pause_request_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id)
            OR NOT EXISTS (SELECT 1 FROM account_users WHERE id = OLD.account_user_id AND account_id = OLD.account_id) THEN
            RETURN OLD;
          END IF;
          RAISE EXCEPTION 'Deferred pause history is immutable';
        END IF;
        IF TG_OP = 'INSERT' THEN
          IF NEW.state <> 'pending' OR NOT EXISTS (SELECT 1 FROM account_users WHERE id = NEW.account_user_id
              AND account_id = NEW.account_id AND user_id = NEW.actor_user_id) THEN
            RAISE EXCEPTION 'Deferred pause actor unavailable';
          END IF;
          IF NEW.queue_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_queues
              WHERE id = NEW.queue_id AND account_id = NEW.account_id) THEN
            RAISE EXCEPTION 'Deferred pause queue unavailable';
          END IF;
          RETURN NEW;
        END IF;
        IF to_jsonb(NEW) - ARRAY['state','failure_code','finished_at','updated_at']
            IS DISTINCT FROM to_jsonb(OLD) - ARRAY['state','failure_code','finished_at','updated_at']
          OR NOT ((OLD.state = 'pending' AND NEW.state IN ('applied', 'blocked', 'cancelled'))
            OR (OLD.state = 'blocked' AND NEW.state = 'cancelled')) THEN
          RAISE EXCEPTION 'Deferred pause request is immutable';
        END IF;
        IF NEW.state = 'applied' AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_agent_state_events
            WHERE account_id = NEW.account_id AND account_user_id = NEW.account_user_id AND state = 'paused'
              AND source = 'jrc_conversas' AND reason_code = NEW.reason_code
              AND external_event_id = 'operator:deferred-pause:' || NEW.request_id::text
              AND metadata -> 'provider_confirmed' = 'false'::jsonb) THEN
          RAISE EXCEPTION 'Deferred pause native event required';
        END IF;
        RETURN NEW;
      END $guard$;
      CREATE TRIGGER cc_deferred_pause_request_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_deferred_pause_requests
        FOR EACH ROW EXECUTE FUNCTION cc_deferred_pause_request_guard();
    SQL
  end

  def schema_receipt
    SchemaReceiptQuery.new(connection).call
  end

  def verify_existing!
    columns = %w[id account_id account_user_id actor_user_id request_id request_digest catalog_revision reason_code reason_label queue_id
                 justification state failure_code finished_at created_at updated_at]
    checks = %w[cc_deferred_pause_failure cc_deferred_pause_identity cc_deferred_pause_state cc_deferred_pause_terminal]
    valid = connection.columns(TABLE).map(&:name).sort == columns.sort && connection.foreign_keys(TABLE).length == 2 &&
            connection.check_constraints(TABLE).map(&:name).sort == checks && connection.table_comment(TABLE) == schema_receipt
    raise ActiveRecord::MigrationError, 'Unexpected deferred pause schema; review before reexecution' unless valid
  end

  # Read-only query kept with the migration so later application changes cannot redefine its receipt.
  class SchemaReceiptQuery
    def initialize(connection)
      @connection = connection
      @table = "#{connection.quote(CreateContactCenterDeferredPauseRequests::TABLE.to_s)}::regclass"
    end

    def call
      "jrc_cc_deferred_pause_v1:#{Digest::SHA256.hexdigest(components.to_json)}"
    end

    private

    def components
      table = CreateContactCenterDeferredPauseRequests::TABLE
      columns = @connection.columns(table).map { |column| [column.name, column.sql_type, column.null, column.default] }
      indexes = @connection.indexes(table).map { |index| [index.name, index.columns, index.unique, index.where] }.sort
      [columns, constraints, triggers, functions, indexes]
    end

    def constraints
      @connection.select_rows('SELECT conname, pg_get_constraintdef(oid, true) FROM pg_constraint ' \
                              "WHERE conrelid = #{@table} ORDER BY conname")
    end

    def triggers
      @connection.select_rows('SELECT tgname, pg_get_triggerdef(oid, true) FROM pg_trigger ' \
                              "WHERE NOT tgisinternal AND tgrelid = #{@table} ORDER BY tgname")
    end

    def functions
      @connection.select_rows('SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE oid IN ' \
                              "(SELECT tgfoid FROM pg_trigger WHERE NOT tgisinternal AND tgrelid = #{@table}) ORDER BY proname")
    end
  end
end
