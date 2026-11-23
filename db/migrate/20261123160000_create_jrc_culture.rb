# frozen_string_literal: true

class CreateJrcCulture < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_culture_grants do |t|
      t.references :account, null: false, foreign_key: true
      t.references :account_user, foreign_key: { on_delete: :nullify }
      t.references :unit, null: false, foreign_key: { to_table: :jrc_crm_business_units }
      t.bigint :member_key, null: false
      t.bigint :user_key, null: false
      t.string :role, null: false, default: 'employee'
      t.string :department, null: false, default: ''
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index %i[account_id member_key unit_id role], unique: true, name: :idx_culture_grant_identity
      t.check_constraint "role IN ('employee', 'administrator')", name: :culture_grant_role
    end

    create_table :jrc_culture_manuals do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :jrc_culture_versions do |t|
      t.references :manual, null: false, foreign_key: { to_table: :jrc_culture_manuals }
      t.integer :number, null: false
      t.string :title, null: false
      t.text :description, null: false, default: ''
      t.string :state, null: false, default: 'draft'
      t.datetime :published_at
      t.timestamps
      t.index %i[manual_id number], unique: true
      t.index :manual_id, unique: true, where: "state = 'published'", name: :idx_culture_current_version
      t.check_constraint "state IN ('draft', 'published', 'inactive', 'withdrawn')", name: :culture_version_state
    end

    create_table :jrc_culture_audiences do |t|
      t.references :version, null: false, foreign_key: { to_table: :jrc_culture_versions }
      t.references :unit, null: false, foreign_key: { to_table: :jrc_crm_business_units }
      t.index %i[version_id unit_id], unique: true
    end

    create_table :jrc_culture_participations do |t|
      t.references :version, null: false, foreign_key: { to_table: :jrc_culture_versions }
      t.references :grant, null: false, foreign_key: { to_table: :jrc_culture_grants }
      t.string :department, null: false, default: ''
      t.datetime :confirmed_at
      t.timestamps
      t.index %i[version_id grant_id], unique: true, name: :idx_culture_participation_identity
    end

    create_table :jrc_culture_assets do |t|
      t.references :version, null: false, foreign_key: { to_table: :jrc_culture_versions }
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }, index: { unique: true }
      t.string :kind, null: false
      t.timestamps
      t.index %i[version_id kind], unique: true
      t.check_constraint "kind IN ('pdf', 'pptx')", name: :culture_asset_kind
    end

    create_table :jrc_culture_imports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :unit, null: false, foreign_key: { to_table: :jrc_crm_business_units }
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }, index: { unique: true }
      t.bigint :actor_id, null: false
      t.datetime :applied_at
      t.jsonb :result
      t.timestamps
    end

    create_table :jrc_culture_events do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :actor_id, null: false
      t.string :action, null: false
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
  end
end
