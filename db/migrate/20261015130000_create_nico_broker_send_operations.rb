class CreateNicoBrokerSendOperations < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_nico_broker_send_operations do |t|
      t.references :command, index: { unique: true }, foreign_key: { to_table: :jrc_nico_commands, on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      %i[account conversation inbox].each { |name| t.references name, null: false, foreign_key: { on_delete: :cascade } }
      t.bigint :actor_id, null: false
      t.references :message, index: { unique: true }, foreign_key: { on_delete: :nullify }
      t.uuid :request_id, :integration_id, null: false
      t.uuid :takeover_id
      t.string :state, null: false, default: 'PREVIEW'
      t.string :fingerprint, null: false
      t.jsonb :snapshot, :recipient_snapshot, null: false, default: {}
      t.string :last_error
      t.integer :attempts, null: false, default: 0
      t.uuid :lease_token
      t.datetime :lease_expires_at, :next_attempt_at, :message_created_at
      t.timestamps
    end
    add_operation_constraints
    protect_creation_fact
  end

  def down
    drop_table :jrc_nico_broker_send_operations
    execute 'DROP FUNCTION IF EXISTS jrc_nico_preserve_send_fact()'
  end

  private

  def add_operation_constraints
    add_index :jrc_nico_broker_send_operations, [:account_id, :request_id], unique: true, name: 'nico_broker_send_request'
    add_index :jrc_nico_broker_send_operations, [:next_attempt_at, :id],
              where: "state IN ('PAUSING','DRAINING','UNKNOWN','MESSAGE_CREATED','CANCELING')", name: 'nico_broker_send_recovery'
    add_check_constraint :jrc_nico_broker_send_operations,
                         "state IN ('PREVIEW','PAUSING','DRAINING','UNKNOWN','MESSAGE_CREATED','COMPLETED','CANCELING','CANCELED','HALTED')",
                         name: 'nico_broker_send_state'
    add_check_constraint :jrc_nico_broker_send_operations,
                         '(lease_token IS NULL) = (lease_expires_at IS NULL)', name: 'nico_broker_send_lease'
    add_check_constraint :jrc_nico_broker_send_operations, 'actor_id > 0', name: 'nico_broker_send_actor'
    add_check_constraint :jrc_nico_broker_send_operations,
                         'message_id IS NULL OR message_created_at IS NOT NULL', name: 'nico_broker_send_message_fact'
    add_check_constraint :jrc_nico_broker_send_operations,
                         "message_created_at IS NULL OR state IN ('MESSAGE_CREATED','COMPLETED','HALTED')", name: 'nico_broker_send_fact_state'
  end

  def protect_creation_fact
    execute <<~SQL.squish
      CREATE FUNCTION jrc_nico_preserve_send_fact() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.actor_id IS DISTINCT FROM OLD.actor_id OR
          (OLD.message_created_at IS NOT NULL AND
            (NEW.message_created_at IS DISTINCT FROM OLD.message_created_at OR
             (NEW.message_id IS NOT NULL AND NEW.message_id IS DISTINCT FROM OLD.message_id))) THEN
          RAISE EXCEPTION 'NICO send identity and Message creation fact are immutable' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER jrc_nico_send_fact_guard BEFORE UPDATE ON jrc_nico_broker_send_operations
      FOR EACH ROW EXECUTE FUNCTION jrc_nico_preserve_send_fact();
    SQL
  end
end
