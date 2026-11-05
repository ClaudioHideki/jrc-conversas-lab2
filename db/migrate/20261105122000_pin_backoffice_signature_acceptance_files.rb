class PinBackofficeSignatureAcceptanceFiles < ActiveRecord::Migration[7.1]
  def up
    execute Rails.root.join('db/functions/20261105122000_backoffice_signature_acceptance.sql').read
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve accepted signature files and their immutable receipts'
  end
end
