# frozen_string_literal: true

# Additive workspace only. Published definitions/rules/versions remain native.
class CreateRelationshipSurveyModelDrafts < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_relationship_survey_model_drafts do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :unit_id, null: false
      t.bigint :definition_id
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :code, null: false, limit: 32
      t.jsonb :payload, null: false, default: {}
      t.jsonb :published_payload, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.string :publication_key, limit: 100
      t.string :publication_digest, limit: 64
      t.datetime :published_at
      t.timestamps
    end
    add_foreign_key :jrc_relationship_survey_model_drafts, :jrc_service_desk_units, column: :unit_id
    add_foreign_key :jrc_relationship_survey_model_drafts, :jrc_relationship_survey_definitions, column: :definition_id
    add_index :jrc_relationship_survey_model_drafts, [:account_id, :unit_id, :code], unique: true, name: 'idx_sd_survey_model_code'
    add_index :jrc_relationship_survey_model_drafts, :definition_id, unique: true, name: 'idx_sd_survey_model_definition'
  end
end
