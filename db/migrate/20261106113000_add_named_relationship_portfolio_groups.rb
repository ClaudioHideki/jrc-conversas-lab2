class AddNamedRelationshipPortfolioGroups < ActiveRecord::Migration[7.1]
  def change
    create_groups
    group_constraints
    create_links
  end

  private

  def group_workflow_fields(table)
    table.string :visibility, null: false, default: 'private'
    table.string :status, null: false, default: 'active'
    table.jsonb :goals, null: false, default: []
    table.integer :lock_version, null: false, default: 0
  end

  def create_groups
    create_table :jrc_relationship_portfolio_groups do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'rel_group_account' }
      t.string :name, null: false
      t.text :objective, null: false, default: ''
      t.bigint :owner_id, null: false
      t.references :team, foreign_key: true
      t.bigint :business_unit_id
      t.bigint :segment_id
      group_workflow_fields(t)
      t.timestamps
      t.index [:account_id, :id], unique: true, name: 'rel_group_tenant_ref'
      t.index [:account_id, :owner_id, :status], name: 'rel_group_owner'
    end
    add_index :jrc_relationship_portfolio_groups, 'account_id, lower(name)', unique: true, name: 'rel_group_unique_name'
  end

  def group_constraints
    add_foreign_key :jrc_relationship_portfolio_groups, :account_users, column: [:account_id, :owner_id],
                                                                        primary_key: [:account_id, :user_id], name: 'rel_group_owner_tenant'
    add_foreign_key :jrc_relationship_portfolio_groups, :jrc_crm_business_units, column: :business_unit_id
    add_foreign_key :jrc_relationship_portfolio_groups, :jrc_customer_taxonomies, column: :segment_id
    add_check_constraint :jrc_relationship_portfolio_groups, "status IN ('active','archived')", name: 'rel_group_status'
    add_check_constraint :jrc_relationship_portfolio_groups, "visibility IN ('private','team','account')", name: 'rel_group_visibility'
    add_check_constraint :jrc_relationship_portfolio_groups, "visibility <> 'team' OR team_id IS NOT NULL", name: 'rel_group_team_visibility'
    add_check_constraint :jrc_relationship_portfolio_groups, "jsonb_typeof(goals) = 'array' AND jsonb_array_length(goals) <= 50",
                         name: 'rel_group_goals'
  end

  def create_links
    create_table :jrc_relationship_portfolio_group_assignments do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'rel_group_link_account' }
      t.bigint :portfolio_group_id, null: false
      t.bigint :assignment_id, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index [:account_id, :portfolio_group_id, :assignment_id], unique: true, name: 'rel_group_unique_customer'
      t.index [:account_id, :assignment_id, :active], name: 'rel_group_customer_scope'
    end
    add_foreign_key :jrc_relationship_portfolio_group_assignments, :jrc_relationship_portfolio_groups,
                    column: [:account_id, :portfolio_group_id], primary_key: [:account_id, :id], name: 'rel_group_link_tenant'
    add_foreign_key :jrc_relationship_portfolio_group_assignments, :jrc_relationship_assignments,
                    column: [:account_id, :assignment_id], primary_key: [:account_id, :id], name: 'rel_group_customer_tenant'
  end
end
