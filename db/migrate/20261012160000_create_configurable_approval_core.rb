class CreateConfigurableApprovalCore < ActiveRecord::Migration[7.1]
  PREFIX = 'jrc_approvals_'.freeze
  TABLES = %w[policies policy_versions requests delegations decisions audit_events].freeze

  def up
    # Additive reference keys; no existing rows, permissions or legacy decisions are changed.
    add_index :jrc_crm_business_units, %i[account_id company_id id], unique: true, name: 'jrc_ap_unit_ref'
    TABLES.each do |kind|
      create_table PREFIX + kind do |t|
        t.bigint :account_id, null: false
        columns(t, kind)
        t.timestamps null: false
      end
      add_index PREFIX + kind, %i[account_id id], unique: true, name: "jrc_ap_#{kind}_ref"
      add_foreign_key PREFIX + kind, :accounts
    end
    add_index :jrc_approvals_policies, %i[account_id code], unique: true, name: 'jrc_ap_policy_code'
    add_index :jrc_approvals_policy_versions, %i[account_id policy_id version], unique: true, name: 'jrc_ap_version_unique'
    add_index :jrc_approvals_policy_versions, %i[account_id policy_id id], unique: true, name: 'jrc_ap_version_parent'
    add_index :jrc_approvals_requests, %i[account_id requester_id request_key policy_version_id], unique: true, name: 'jrc_ap_request_once'
    add_index :jrc_approvals_decisions, %i[account_id actor_id idempotency_key], unique: true, name: 'jrc_ap_decision_once'
    add_index :jrc_approvals_decisions, %i[request_id cycle step_code principal_id], unique: true, name: 'jrc_ap_principal_vote'
    add_index :jrc_approvals_decisions, %i[request_id cycle step_code actor_id], unique: true, name: 'jrc_ap_actor_vote'
    add_index :jrc_approvals_audit_events, %i[account_id correlation_key], unique: true, name: 'jrc_ap_audit_once'
    add_index :jrc_approvals_requests, %i[account_id state expires_at], name: 'jrc_ap_pending'
    add_foreign_key :jrc_approvals_policies, :jrc_approvals_policy_versions,
                    column: %i[account_id id current_version_id], primary_key: %i[account_id policy_id id], name: 'jrc_ap_policy_version_parent_fk'
    scoped_fk('policy_versions', 'policies', 'policy_id')
    scoped_fk('requests', 'policy_versions', 'policy_version_id')
    scoped_fk('decisions', 'requests', 'request_id')
    scoped_fk('decisions', 'delegations', 'delegation_id')
    scoped_fk('delegations', 'policy_versions', 'policy_version_id')
    %w[request_id policy_id policy_version_id decision_id].zip(%w[requests policies policy_versions decisions]).each do |column, target|
      scoped_fk('audit_events', target, column)
    end
    { 'policies' => %w[author_id], 'policy_versions' => %w[publisher_id], 'requests' => %w[requester_id],
      'decisions' => %w[actor_id principal_id], 'delegations' => %w[grantor_id principal_id delegate_id],
      'audit_events' => %w[actor_id] }.each do |kind, columns|
      columns.each do |column|
        add_foreign_key PREFIX + kind, :account_users, column: [:account_id, column], primary_key: %i[account_id id],
                        name: "jrc_ap_#{kind}_#{column}_fk"
      end
    end
    %w[policies requests].each do |kind|
      add_foreign_key PREFIX + kind, :companies, column: %i[account_id issuer_company_id], primary_key: %i[account_id id],
                      name: "jrc_ap_#{kind}_company_fk"
      add_foreign_key PREFIX + kind, :jrc_crm_business_units, column: %i[account_id issuer_company_id business_unit_id],
                      primary_key: %i[account_id company_id id], name: "jrc_ap_#{kind}_unit_fk"
      add_check_constraint PREFIX + kind, 'business_unit_id IS NULL OR issuer_company_id IS NOT NULL', name: "jrc_ap_#{kind}_scope"
    end
    add_check_constraint :jrc_approvals_policies, "state IN ('draft','validated','published','retired')", name: 'jrc_ap_policy_state'
    add_check_constraint :jrc_approvals_policy_versions, 'version > 0', name: 'jrc_ap_version_positive'
    add_check_constraint :jrc_approvals_requests,
                         "state IN ('pending','approved','rejected','returned','escalated','expired','canceled','stale') AND cycle > 0",
                         name: 'jrc_ap_request_state'
    add_check_constraint :jrc_approvals_decisions, "decision IN ('approved','rejected','returned','escalated') AND cycle > 0",
                         name: 'jrc_ap_decision_state'
    add_check_constraint :jrc_approvals_decisions, "length(trim(reason)) > 0", name: 'jrc_ap_decision_reason'
    add_check_constraint :jrc_approvals_delegations, 'ends_at > starts_at AND principal_id <> delegate_id', name: 'jrc_ap_delegation_window'
    execute <<~SQL
      CREATE FUNCTION jrc_ap_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN RAISE EXCEPTION 'Approval history is immutable'; END; $$;
      CREATE FUNCTION jrc_ap_request_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'Approval request history cannot be deleted'; END IF;
        IF (to_jsonb(NEW) - ARRAY['state','lock_version','cycle','updated_at']) IS DISTINCT FROM
           (to_jsonb(OLD) - ARRAY['state','lock_version','cycle','updated_at']) THEN
          RAISE EXCEPTION 'Approval snapshot is immutable';
        END IF;
        IF NEW.lock_version <> OLD.lock_version + 1 THEN RAISE EXCEPTION 'Approval version must advance'; END IF;
        IF OLD.state <> 'pending' AND NOT (OLD.state IN ('returned','escalated') AND NEW.state IN ('pending','canceled','stale')) AND
           NOT (OLD.state = 'approved' AND NEW.state = 'stale') THEN
          RAISE EXCEPTION 'Terminal approval cannot be changed';
        END IF;
        RETURN NEW;
      END; $$;
    SQL
    %w[policy_versions decisions audit_events].each do |kind|
      execute "CREATE TRIGGER jrc_ap_immutable BEFORE UPDATE OR DELETE ON #{PREFIX + kind} FOR EACH ROW EXECUTE FUNCTION jrc_ap_immutable()"
    end
    execute 'CREATE TRIGGER jrc_ap_request_guard BEFORE UPDATE OR DELETE ON jrc_approvals_requests ' \
            'FOR EACH ROW EXECUTE FUNCTION jrc_ap_request_guard()'
  end

  def down
    TABLES.reverse_each { |kind| drop_table PREFIX + kind, force: :cascade }
    execute 'DROP FUNCTION jrc_ap_request_guard()'
    execute 'DROP FUNCTION jrc_ap_immutable()'
    remove_index :jrc_crm_business_units, name: 'jrc_ap_unit_ref'
  end

  private

  def scoped_fk(kind, target, column)
    add_foreign_key PREFIX + kind, PREFIX + target, column: [:account_id, column], primary_key: %i[account_id id],
                    name: "jrc_ap_#{kind}_#{column}_fk"
  end

  def columns(t, kind)
    case kind
    when 'policies'
      %i[issuer_company_id business_unit_id current_version_id].each { |name| t.bigint name }
      t.bigint :author_id, null: false
      %i[code name module_key event_key].each { |name| t.string name, null: false }
      t.string :state, null: false, default: 'draft'
      t.boolean :enabled, null: false, default: false
      t.jsonb :draft_definition, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
    when 'policy_versions'
      %i[policy_id publisher_id].each { |name| t.bigint name, null: false }
      t.integer :version, null: false
      t.jsonb :definition, null: false
      t.jsonb :publication, null: false
      t.string :digest, null: false
    when 'requests'
      %i[policy_version_id requester_id resource_id].each { |name| t.bigint name, null: false }
      %i[issuer_company_id business_unit_id].each { |name| t.bigint name }
      %i[resource_type module_key event_key request_key input_digest fingerprint].each { |name| t.string name, null: false }
      t.jsonb :snapshot, null: false
      t.jsonb :stage_plan, null: false
      t.string :state, null: false, default: 'pending'
      t.datetime :expires_at, null: false
      t.integer :lock_version, null: false, default: 0
      t.integer :cycle, null: false, default: 1
    when 'delegations'
      %i[policy_version_id grantor_id principal_id delegate_id].each { |name| t.bigint name, null: false }
      t.string :step_code, null: false
      t.jsonb :actions, null: false
      t.text :reason, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.datetime :revoked_at
    when 'decisions'
      %i[request_id actor_id principal_id].each { |name| t.bigint name, null: false }
      t.bigint :delegation_id
      %i[step_code decision idempotency_key payload_digest].each { |name| t.string name, null: false }
      t.text :reason, null: false
      t.integer :cycle, null: false
      t.integer :expected_version, null: false
    when 'audit_events'
      %i[request_id policy_id policy_version_id decision_id].each { |name| t.bigint name }
      t.bigint :actor_id, null: false
      %i[event_type correlation_key].each { |name| t.string name, null: false }
      t.jsonb :data, null: false
    end
  end
end
