class AddJrcCrmOrganizationalStructure < ActiveRecord::Migration[7.1]
  def up
    add_reference :jrc_crm_business_units, :company, foreign_key: { to_table: :companies }, index: false
    add_index :jrc_crm_business_units, [:account_id, :id], unique: true, name: 'jrc_crm_bu_account_id_unique'
    add_index :jrc_crm_business_units, [:account_id, :company_id], name: 'idx_jrc_crm_bu_company'
    add_foreign_key :jrc_crm_business_units, :companies,
                    column: [:account_id, :company_id], primary_key: [:account_id, :id],
                    validate: false, name: 'jrc_crm_bu_company_account_fk'

    change_column_null :jrc_crm_user_business_units, :business_unit_id, true
    add_reference :jrc_crm_user_business_units, :company, foreign_key: { to_table: :companies }, index: false
    add_reference :jrc_crm_user_business_units, :team, foreign_key: true, index: false
    add_column :jrc_crm_user_business_units, :active, :boolean, null: false, default: true
    add_column :jrc_crm_user_business_units, :structure_managed, :boolean, null: false, default: false
    remove_index :jrc_crm_user_business_units, name: 'idx_jrc_crm_user_bu_unique', if_exists: true
    add_index :jrc_crm_user_business_units, [:account_id, :user_id], name: 'idx_jrc_crm_user_scope_user'
    add_index :jrc_crm_user_business_units, [:account_id, :team_id], name: 'idx_jrc_crm_user_scope_team'
    add_index :jrc_crm_user_business_units, [:account_id, :company_id], name: 'idx_jrc_crm_user_scope_company'
    add_index :jrc_crm_user_business_units, [:account_id, :business_unit_id], name: 'idx_jrc_crm_user_scope_unit'
    add_index :jrc_crm_user_business_units, "account_id, user_id, COALESCE(team_id, 0)", unique: true,
              where: "structure_managed = TRUE AND active = TRUE AND scope = 'GROUP'",
              name: 'idx_jrc_crm_user_scope_group_unique'
    add_index :jrc_crm_user_business_units, "account_id, user_id, COALESCE(team_id, 0), company_id", unique: true,
              where: "structure_managed = TRUE AND active = TRUE AND scope = 'COMPANY'",
              name: 'idx_jrc_crm_user_scope_company_unique'
    add_index :jrc_crm_user_business_units, "account_id, user_id, COALESCE(team_id, 0), business_unit_id", unique: true,
              where: "structure_managed = TRUE AND active = TRUE AND scope = 'BUSINESS_UNIT'",
              name: 'idx_jrc_crm_user_scope_unit_unique'
    add_foreign_key :jrc_crm_user_business_units, :companies,
                    column: [:account_id, :company_id], primary_key: [:account_id, :id],
                    validate: false, name: 'jrc_crm_user_scope_company_account_fk'
    add_foreign_key :jrc_crm_user_business_units, :jrc_crm_business_units,
                    column: [:account_id, :business_unit_id], primary_key: [:account_id, :id],
                    validate: false, name: 'jrc_crm_user_scope_unit_account_fk'
    add_foreign_key :jrc_crm_user_business_units, :teams,
                    column: [:account_id, :team_id], primary_key: [:account_id, :id],
                    validate: false, name: 'jrc_crm_user_scope_team_account_fk'

    create_table :jrc_crm_team_scopes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.bigint :company_id
      t.bigint :business_unit_id
      t.string :scope, null: false, default: 'GROUP'
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :jrc_crm_team_scopes, [:account_id, :team_id], name: 'idx_jrc_crm_team_scope_team'
    add_index :jrc_crm_team_scopes, [:account_id, :company_id], name: 'idx_jrc_crm_team_scope_company'
    add_index :jrc_crm_team_scopes, [:account_id, :business_unit_id], name: 'idx_jrc_crm_team_scope_unit'
    add_index :jrc_crm_team_scopes, [:team_id], unique: true, where: "scope = 'GROUP' AND active = TRUE",
              name: 'idx_jrc_crm_team_scope_group_unique'
    add_index :jrc_crm_team_scopes, [:team_id, :company_id], unique: true,
              where: "scope = 'COMPANY' AND active = TRUE", name: 'idx_jrc_crm_team_scope_company_unique'
    add_index :jrc_crm_team_scopes, [:team_id, :business_unit_id], unique: true,
              where: "scope = 'BUSINESS_UNIT' AND active = TRUE", name: 'idx_jrc_crm_team_scope_unit_unique'
    add_foreign_key :jrc_crm_team_scopes, :companies,
                    column: [:account_id, :company_id], primary_key: [:account_id, :id],
                    validate: false, name: 'jrc_crm_team_scope_company_account_fk'
    add_foreign_key :jrc_crm_team_scopes, :jrc_crm_business_units,
                    column: [:account_id, :business_unit_id], primary_key: [:account_id, :id],
                    validate: false, name: 'jrc_crm_team_scope_unit_account_fk'
    add_foreign_key :jrc_crm_team_scopes, :teams,
                    column: [:account_id, :team_id], primary_key: [:account_id, :id],
                    validate: false, name: 'jrc_crm_team_scope_team_account_fk'

    add_check_constraint :jrc_crm_team_scopes,
                         "(scope = 'GROUP' AND company_id IS NULL AND business_unit_id IS NULL) OR " \
                         "(scope = 'COMPANY' AND company_id IS NOT NULL AND business_unit_id IS NULL) OR " \
                         "(scope = 'BUSINESS_UNIT' AND business_unit_id IS NOT NULL)",
                         name: 'jrc_crm_team_scope_shape'

    add_check_constraint :jrc_crm_user_business_units,
                         "structure_managed = FALSE OR " \
                         "(scope = 'GROUP' AND company_id IS NULL AND business_unit_id IS NULL) OR " \
                         "(scope = 'COMPANY' AND company_id IS NOT NULL AND business_unit_id IS NULL) OR " \
                         "(scope = 'BUSINESS_UNIT' AND business_unit_id IS NOT NULL)",
                         name: 'jrc_crm_user_scope_shape'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Organizational scopes may contain reviewed production assignments; disable the feature instead of rolling back schema.'
  end
end
