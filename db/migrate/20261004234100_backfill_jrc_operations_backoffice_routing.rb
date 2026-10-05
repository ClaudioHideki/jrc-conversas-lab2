class BackfillJrcOperationsBackofficeRouting < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      INSERT INTO jrc_operations_queues
        (account_id, name, code, assignment_strategy, active, settings, created_at, updated_at)
      SELECT DISTINCT requests.account_id, 'Backoffice Geral', 'BACKOFFICE-GERAL', 'manual', TRUE,
             '{"system_default":true}'::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM jrc_crm_backoffice_requests requests
      WHERE NOT EXISTS (
        SELECT 1 FROM jrc_operations_queues queues
        WHERE queues.account_id = requests.account_id AND queues.code = 'BACKOFFICE-GERAL'
      )
    SQL

    execute <<~SQL
      INSERT INTO jrc_operations_sla_policies
        (account_id, operations_queue_id, name, scope_kind, active, conditions, business_hours,
         pause_statuses, alert_thresholds, escalation, created_at, updated_at)
      SELECT queues.account_id, queues.id, 'Backoffice — configurar SLA', 'backoffice', TRUE,
             '{"system_default":true,"monitor_only":true}'::jsonb, '{"enabled":false}'::jsonb,
             '["waiting_customer"]'::jsonb, '[50,75,90,100]'::jsonb, '{}'::jsonb,
             CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM jrc_operations_queues queues
      WHERE queues.code = 'BACKOFFICE-GERAL'
        AND EXISTS (SELECT 1 FROM jrc_crm_backoffice_requests requests WHERE requests.account_id = queues.account_id)
        AND NOT EXISTS (
          SELECT 1 FROM jrc_operations_sla_policies policies
          WHERE policies.account_id = queues.account_id
            AND policies.scope_kind = 'backoffice'
            AND policies.name = 'Backoffice — configurar SLA'
        )
    SQL

    execute <<~SQL
      UPDATE jrc_crm_backoffice_requests requests
      SET operations_queue_id = COALESCE(requests.operations_queue_id, queues.id),
          operations_sla_policy_id = COALESCE(requests.operations_sla_policy_id, policies.id),
          updated_at = CURRENT_TIMESTAMP
      FROM jrc_operations_queues queues
      JOIN jrc_operations_sla_policies policies
        ON policies.account_id = queues.account_id
       AND policies.scope_kind = 'backoffice'
       AND policies.name = 'Backoffice — configurar SLA'
       AND policies.operations_queue_id = queues.id
      WHERE requests.account_id = queues.account_id
        AND queues.code = 'BACKOFFICE-GERAL'
        AND (requests.operations_queue_id IS NULL OR requests.operations_sla_policy_id IS NULL)
    SQL
  end

  def down
    # Routing records are operational data. The structural migration removes the
    # references/tables when the whole feature is rolled back.
  end
end
