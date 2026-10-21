# frozen_string_literal: true

class ExtendContactCenterQualificationsForAcw < ActiveRecord::Migration[7.1]
  def up
    change_column_null :jrc_contact_center_qualifications, :call_session_id, true
    change_column_null :jrc_contact_center_qualifications, :outcome_code, true
    add_column :jrc_contact_center_qualifications, :conversation_id, :integer
    add_column :jrc_contact_center_qualifications, :conversation_cycle, :integer, null: false, default: 0
    add_column :jrc_contact_center_qualifications, :channel, :string, null: false, default: 'voice'
    add_column :jrc_contact_center_qualifications, :started_at, :datetime
    add_column :jrc_contact_center_qualifications, :completed_at, :datetime
    add_column :jrc_contact_center_qualifications, :acw_limit_seconds, :integer
    add_column :jrc_contact_center_qualifications, :duration_seconds, :integer
    add_column :jrc_contact_center_qualifications, :overdue, :boolean, null: false, default: false
    add_column :jrc_contact_center_qualifications, :exceeded_seconds, :integer, null: false, default: 0
    # Existing qualifications remain completed historical outcomes, not new pending work.
    execute 'UPDATE jrc_contact_center_qualifications SET completed_at = created_at'
    add_foreign_key :jrc_contact_center_qualifications, :conversations, column: [:account_id, :conversation_id],
                    primary_key: %i[account_id id], name: 'jrc_cc_qualification_conversation_fk'
    add_index :jrc_contact_center_qualifications, %i[account_id conversation_id account_user_id conversation_cycle],
              unique: true, where: 'conversation_id IS NOT NULL', name: 'jrc_cc_qualification_conversation_once'
    add_index :jrc_contact_center_qualifications, %i[account_id account_user_id],
              where: 'completed_at IS NULL', name: 'jrc_cc_qualification_pending'
    add_check_constraint :jrc_contact_center_qualifications,
                         "(channel = 'voice' AND call_session_id IS NOT NULL AND conversation_id IS NULL) OR " \
                         "(channel = 'whatsapp' AND conversation_id IS NOT NULL AND call_session_id IS NULL)", name: 'jrc_cc_qualification_target'
    add_check_constraint :jrc_contact_center_qualifications,
                         'started_at IS NULL OR (acw_limit_seconds > 0 AND (completed_at IS NULL OR ' \
                         "(completed_at >= started_at AND length(trim(reason_code)) > 0 AND length(trim(outcome_code)) > 0)))",
                         name: 'jrc_cc_qualification_completion'
  end

  def down
    unsupported = select_value('SELECT EXISTS (SELECT 1 FROM jrc_contact_center_qualifications WHERE conversation_id IS NOT NULL OR outcome_code IS NULL)')
    raise ActiveRecord::IrreversibleMigration, 'ACW records must be retained; rollback would discard operational data' if unsupported

    remove_check_constraint :jrc_contact_center_qualifications, name: 'jrc_cc_qualification_completion'
    remove_check_constraint :jrc_contact_center_qualifications, name: 'jrc_cc_qualification_target'
    remove_foreign_key :jrc_contact_center_qualifications, name: 'jrc_cc_qualification_conversation_fk'
    remove_index :jrc_contact_center_qualifications, name: 'jrc_cc_qualification_conversation_once'
    remove_index :jrc_contact_center_qualifications, name: 'jrc_cc_qualification_pending'
    %i[conversation_id conversation_cycle channel started_at completed_at acw_limit_seconds duration_seconds overdue exceeded_seconds].each do |column|
      remove_column :jrc_contact_center_qualifications, column
    end
    change_column_null :jrc_contact_center_qualifications, :outcome_code, false
    change_column_null :jrc_contact_center_qualifications, :call_session_id, false
  end
end
