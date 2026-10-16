class FenceNativeInboxResponders < ActiveRecord::Migration[7.1]
  def up
    add_column :jrc_flow_ownership_epochs, :broker_agent_bot_id, :bigint
    add_column :jrc_flow_ownership_epochs, :broker_agent_bot_callback, :text
    add_check_constraint :jrc_flow_ownership_epochs,
                         '(broker_agent_bot_id IS NULL AND broker_agent_bot_callback IS NULL) ' \
                         'OR (broker_agent_bot_id>0 AND broker_agent_bot_callback IS NOT NULL)',
                         name: 'jrc_ownership_bot_pair'
    add_column :jrc_flow_ownership_executions, :authority_kind, :string, null: false, default: 'LEGACY'
    add_column :jrc_flow_ownership_executions, :authority_bot_id, :bigint
    add_column :jrc_flow_ownership_executions, :authority_epoch_id, :bigint
    add_check_constraint :jrc_flow_ownership_executions,
                         "(authority_kind='LEGACY' AND authority_bot_id IS NULL AND authority_epoch_id IS NULL) OR " \
                         "(authority_kind='BROKER_CALLBACK' AND authority_bot_id>0 AND authority_epoch_id>0)",
                         name: 'jrc_ownership_execution_authority'
    execute File.read(Rails.root.join('db/functions/20261015160000_native_responder_config_fence.sql'))
    execute 'CREATE TRIGGER jrc_native_agent_bot_inbox_fence BEFORE INSERT OR UPDATE OR DELETE ON agent_bot_inboxes ' \
            'FOR EACH ROW EXECUTE FUNCTION jrc_native_responder_config_fence()'
    execute 'CREATE TRIGGER jrc_native_agent_bot_fence BEFORE UPDATE OR DELETE ON agent_bots ' \
            'FOR EACH ROW EXECUTE FUNCTION jrc_native_responder_config_fence()'
    execute 'CREATE TRIGGER jrc_native_conversation_bot_fence BEFORE INSERT OR UPDATE ON conversations ' \
            'FOR EACH ROW EXECUTE FUNCTION jrc_native_responder_config_fence()'
    execute 'CREATE TRIGGER jrc_native_inbox_policy_fence BEFORE INSERT OR UPDATE ON inboxes ' \
            'FOR EACH ROW EXECUTE FUNCTION jrc_native_responder_config_fence()'
  end

  def down
    execute 'DROP TRIGGER IF EXISTS jrc_native_agent_bot_inbox_fence ON agent_bot_inboxes'
    execute 'DROP TRIGGER IF EXISTS jrc_native_agent_bot_fence ON agent_bots'
    execute 'DROP TRIGGER IF EXISTS jrc_native_conversation_bot_fence ON conversations'
    execute 'DROP TRIGGER IF EXISTS jrc_native_inbox_policy_fence ON inboxes'
    execute 'DROP FUNCTION IF EXISTS jrc_native_responder_config_fence()'
    remove_check_constraint :jrc_flow_ownership_executions, name: 'jrc_ownership_execution_authority'
    remove_columns :jrc_flow_ownership_executions, :authority_kind, :authority_bot_id, :authority_epoch_id
    remove_check_constraint :jrc_flow_ownership_epochs, name: 'jrc_ownership_bot_pair'
    remove_columns :jrc_flow_ownership_epochs, :broker_agent_bot_id, :broker_agent_bot_callback
  end
end
