# frozen_string_literal: true

# Run with application writers stopped: old and new releases interpret bit 256 differently.
class RelocateJrcBrokerFeatureFlag < ActiveRecord::Migration[7.1]
  def up
    transfer_bit(from: 256, to: 1024)
  end

  def down
    # Once Service Desk is explicitly enabled, rollback requires an operator decision.
    # Refuse rather than interpreting that entitlement as the old Broker flag.
    transfer_bit(from: 1024, to: 256)
  end

  private

  def transfer_bit(from:, to:)
    execute 'LOCK TABLE accounts IN ACCESS EXCLUSIVE MODE'
    occupied = select_value("SELECT EXISTS (SELECT 1 FROM accounts WHERE (feature_flags_ext_1 & #{to}) <> 0)")
    raise ActiveRecord::IrreversibleMigration, "Destination feature mask #{to} is occupied; no account was changed" if occupied

    execute <<~SQL.squish
      UPDATE accounts
      SET feature_flags_ext_1 = (feature_flags_ext_1 | #{to}) & ~#{from}::bigint
      WHERE (feature_flags_ext_1 & #{from}) <> 0
    SQL
  end
end
