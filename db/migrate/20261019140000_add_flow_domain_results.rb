class AddFlowDomainResults < ActiveRecord::Migration[7.1]
  def up
    add_column :jrc_flow_effect_receipts, :domain_result, :jsonb
    remove_check_constraint :jrc_flow_effect_receipts, name: 'jrc_effect_operation'
    add_check_constraint :jrc_flow_effect_receipts, "operation IN ('tag','attribute','note','resolve','domain')", name: 'jrc_effect_operation'
    add_check_constraint :jrc_flow_effect_receipts,
                         "(operation='domain')=(domain_result IS NOT NULL) AND " \
                         "(domain_result IS NULL OR jsonb_typeof(domain_result)='object' AND octet_length(domain_result::text)<=4096)",
                         name: 'jrc_effect_domain_result'
  end

  def down
    if select_value("SELECT EXISTS(SELECT 1 FROM jrc_flow_effect_receipts WHERE operation='domain')")
      raise ActiveRecord::IrreversibleMigration, 'Preserve confirmed domain receipts; application rollback may retain this additive schema'
    end

    remove_check_constraint :jrc_flow_effect_receipts, name: 'jrc_effect_domain_result'
    remove_check_constraint :jrc_flow_effect_receipts, name: 'jrc_effect_operation'
    add_check_constraint :jrc_flow_effect_receipts, "operation IN ('tag','attribute','note','resolve')", name: 'jrc_effect_operation'
    remove_column :jrc_flow_effect_receipts, :domain_result
  end
end
