class AllowJrcFlowExecutionInspectionScope < ActiveRecord::Migration[7.1]
  def up
    replace_scope_constraint(%w[flow:read flow:edit flow:publish flow:bind flow:executions:read])
  end

  def down
    # Never silently remove grants. Rollback fails if new-capability handles remain.
    replace_scope_constraint(%w[flow:read flow:edit flow:publish flow:bind])
  end

  private

  def replace_scope_constraint(scopes)
    remove_check_constraint :jrc_flow_native_session_handles, name: 'jrc_flow_handle_scope_bound'
    add_check_constraint :jrc_flow_native_session_handles,
                         "registration_revision>0 AND jsonb_typeof(inbox_ids)='array' AND jsonb_array_length(inbox_ids)<=100 " \
                         "AND jsonb_typeof(scopes)='array' AND scopes <@ '#{scopes.to_json}'::jsonb",
                         name: 'jrc_flow_handle_scope_bound'
  end
end
