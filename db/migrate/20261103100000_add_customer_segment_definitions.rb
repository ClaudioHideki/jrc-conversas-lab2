class AddCustomerSegmentDefinitions < ActiveRecord::Migration[7.1]
  def up
    add_definition
    add_overrides
  end

  def down
    used = select_value(<<~SQL.squish)
      SELECT id FROM jrc_customer_taxonomies
      WHERE description IS NOT NULL OR selection_mode <> 'classification' OR cardinality(modules) > 0
         OR criteria <> '{"match":"all","rules":[]}'::jsonb
      LIMIT 1
    SQL
    overrides = select_value('SELECT id FROM jrc_customer_segment_overrides LIMIT 1')
    raise ActiveRecord::IrreversibleMigration, 'Preserve segment definitions and overrides before rollback' if used || overrides

    drop_table :jrc_customer_segment_overrides
    remove_check_constraint :jrc_customer_taxonomies, name: 'customer_segment_selection_mode'
    %i[modules criteria selection_mode description].each { |column| remove_column :jrc_customer_taxonomies, column }
  end

  private

  def add_definition
    add_column :jrc_customer_taxonomies, :description, :text
    add_column :jrc_customer_taxonomies, :selection_mode, :string, null: false, default: 'classification'
    add_column :jrc_customer_taxonomies, :criteria, :jsonb, null: false, default: { match: 'all', rules: [] }
    add_column :jrc_customer_taxonomies, :modules, :string, array: true, null: false, default: []
    add_check_constraint :jrc_customer_taxonomies, "selection_mode IN ('classification', 'dynamic')", name: 'customer_segment_selection_mode'
  end

  def add_overrides
    create_table :jrc_customer_segment_overrides do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :taxonomy, null: false, foreign_key: { to_table: :jrc_customer_taxonomies, on_delete: :cascade }
      t.references :company, foreign_key: { on_delete: :cascade }
      t.references :contact, type: :integer, foreign_key: { on_delete: :cascade }
      t.string :mode, null: false
      t.timestamps
    end
    add_check_constraint :jrc_customer_segment_overrides,
                         '(company_id IS NULL) <> (contact_id IS NULL)', name: 'customer_segment_override_subject'
    add_check_constraint :jrc_customer_segment_overrides, "mode IN ('include', 'exclude')", name: 'customer_segment_override_mode'
    add_index :jrc_customer_segment_overrides, %i[taxonomy_id company_id], unique: true,
                                                                           where: 'company_id IS NOT NULL', name: 'customer_segment_company_override'
    add_index :jrc_customer_segment_overrides, %i[taxonomy_id contact_id], unique: true,
                                                                           where: 'contact_id IS NOT NULL', name: 'customer_segment_contact_override'
  end
end
