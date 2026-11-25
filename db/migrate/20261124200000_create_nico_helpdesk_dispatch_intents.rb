# frozen_string_literal: true

# Empty technical intents only; no Event backfill, policy activation or grants.
class CreateNicoHelpdeskDispatchIntents < ActiveRecord::Migration[7.1]
  def change
    add_index :jrc_nico_helpdesk_events, %i[account_id id], unique: true, name: 'nico_hd_event_account_identity'
    create_table :jrc_nico_helpdesk_dispatch_intents do |t|
      t.bigint :account_id, null: false
      t.bigint :event_id, null: false
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index :jrc_nico_helpdesk_dispatch_intents, :event_id, unique: true, name: 'nico_hd_dispatch_event_once'
    add_index :jrc_nico_helpdesk_dispatch_intents, %i[account_id created_at], name: 'nico_hd_dispatch_pending'
    add_foreign_key :jrc_nico_helpdesk_dispatch_intents, :accounts, on_delete: :cascade
    add_foreign_key :jrc_nico_helpdesk_dispatch_intents, :jrc_nico_helpdesk_events,
                    column: %i[account_id event_id], primary_key: %i[account_id id],
                    on_delete: :cascade, name: 'nico_hd_dispatch_event_scope'
  end
end
