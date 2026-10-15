class BoundJrcFlowEditorHandles < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_flow_native_session_handles, :inbox_ids, :jsonb, null: false, default: []
    add_column :jrc_flow_native_session_handles, :scopes, :jsonb, null: false, default: []
    add_column :jrc_flow_native_session_handles, :registration_revision, :integer, null: false, default: 1
    # Existing handles have no persisted approved scope, so expire on upgrade.
    reversible do |direction|
      direction.up do
        execute 'UPDATE jrc_flow_native_session_handles SET closed_at=COALESCE(closed_at,clock_timestamp()), ' \
                'encrypted_session_bearer=NULL, remote_close_pending=true'
      end
    end
    add_check_constraint :jrc_flow_native_session_handles,
                         "registration_revision>0 AND jsonb_typeof(inbox_ids)='array' AND jsonb_array_length(inbox_ids)<=100 " \
                         "AND jsonb_typeof(scopes)='array' AND scopes <@ '[\"flow:read\",\"flow:edit\",\"flow:publish\",\"flow:bind\"]'::jsonb",
                         name: 'jrc_flow_handle_scope_bound'
  end
end
