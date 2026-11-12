class CreateApprovalNotificationOutboxes < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_approvals_notification_outboxes do |t|
      t.bigint :account_id, null: false
      t.bigint :source_event_id, null: false
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps null: false
    end
    add_index :jrc_approvals_notification_outboxes, %i[account_id source_event_id], unique: true, name: 'jrc_ap_notice_source_once'
    add_index :jrc_approvals_notification_outboxes, :id, where: 'completed_at IS NULL', name: 'jrc_ap_notice_pending'
    add_foreign_key :jrc_approvals_notification_outboxes, :accounts
    add_foreign_key :jrc_approvals_notification_outboxes, :jrc_approvals_audit_events,
                    column: %i[account_id source_event_id], primary_key: %i[account_id id], name: 'jrc_ap_notice_source_fk'
    protect_source_and_completion
  end

  def protect_source_and_completion
    execute <<~SQL.squish
      CREATE FUNCTION jrc_ap_notice_source_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.account_id, NEW.source_event_id, NEW.created_at) IS DISTINCT FROM
           ROW(OLD.account_id, OLD.source_event_id, OLD.created_at) OR
           (OLD.completed_at IS NOT NULL AND NEW.completed_at IS DISTINCT FROM OLD.completed_at) THEN
          RAISE EXCEPTION 'Approval notification source and completion are immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER jrc_ap_notice_source_guard BEFORE UPDATE ON jrc_approvals_notification_outboxes
        FOR EACH ROW EXECUTE FUNCTION jrc_ap_notice_source_guard();
    SQL
  end

  def down
    drop_table :jrc_approvals_notification_outboxes
    execute 'DROP FUNCTION jrc_ap_notice_source_guard()'
  end
end
