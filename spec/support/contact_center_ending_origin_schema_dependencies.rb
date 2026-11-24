# Test-only DDL dependency handling. Call exclusively inside the existing
# rollbackable migration examples; production foreign keys are never removed.
module ContactCenterEndingOriginSchemaDependencies
  def detach_ending_origin_version_reference
    connection = ApplicationRecord.connection
    connection.execute('SET CONSTRAINTS cc_ending_readiness_version_fk IMMEDIATE')
    connection.remove_foreign_key(:jrc_contact_center_ending_action_readinesses, name: 'cc_ending_readiness_version_fk')
    ApplicationRecord.connection.remove_foreign_key(:jrc_contact_center_ending_action_origins,
                                                    name: 'cc_ending_execution_origin_version_fk')
  end

  def detach_ending_origin_scope_references
    connection = ApplicationRecord.connection
    # Validate this owned deferred FK before fixture-only DDL. Never disable it
    # or alter the runtime deferrability; the enclosing test rolls back the DDL.
    connection.execute('SET CONSTRAINTS cc_ending_execution_leg_scope_fk IMMEDIATE')
    connection.remove_foreign_key(:jrc_contact_center_call_legs, name: 'cc_ending_execution_leg_scope_fk')
    connection.remove_foreign_key(:jrc_contact_center_ending_action_origins, name: 'cc_ending_execution_origin_scope_fk')
    %i[jrc_contact_center_ending_action_origins jrc_contact_center_ending_action_completions].each do |table|
      connection.remove_foreign_key(table, :jrc_contact_center_ending_scope_accounts)
    end
    connection.remove_foreign_key(:jrc_contact_center_ending_action_readinesses, :jrc_contact_center_ending_scope_accounts)
    connection.remove_foreign_key(:jrc_contact_center_ending_action_executions, :jrc_contact_center_ending_scope_accounts)
  end
end
