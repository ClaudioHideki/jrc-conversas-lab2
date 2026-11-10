class AllowTypedBackofficeHumanResponses < ActiveRecord::Migration[7.1]
  def up
    execute File.read(Rails.root.join('db/functions/20261110190000_backoffice_human_requirement_guard.sql'))
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve typed human responses and their immutable review history'
  end
end
