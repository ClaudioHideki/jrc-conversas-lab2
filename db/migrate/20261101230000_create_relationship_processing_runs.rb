class CreateRelationshipProcessingRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_relationship_processing_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :viewer, null: false, foreign_key: { to_table: :users }
      t.string :access_signature, null: false
      t.string :state, null: false, default: 'running'
      t.jsonb :requested_ids, null: false, default: []
      t.jsonb :outcomes, null: false, default: {}
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.timestamps
    end
    add_index :jrc_relationship_processing_runs, [:account_id, :viewer_id, :created_at], name: 'rel_processing_viewer_history'
  end
end
