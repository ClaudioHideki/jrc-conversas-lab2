# == Schema Information
#
# Table name: jrc_crm_backoffice_requests
#
#  id               :bigint           not null, primary key
#  completed_at     :datetime
#  description      :text
#  due_at           :datetime
#  metadata         :jsonb            not null
#  priority         :string           default("normal"), not null
#  request_kind     :string           default("fulfillment"), not null
#  request_number   :string           not null
#  stage            :string           default("analysis"), not null
#  status           :string           default("pending"), not null
#  title            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  business_unit_id :bigint
#  contact_id       :bigint
#  contract_id      :bigint
#  owner_id         :bigint           not null
#  requested_by_id  :bigint           not null
#  sales_order_id   :bigint           not null
#
# Indexes
#
#  idx_jrc_crm_backoffice_number                          (account_id,request_number) UNIQUE
#  idx_jrc_crm_backoffice_order_kind                      (account_id,sales_order_id,request_kind) UNIQUE WHERE ((request_kind)::text = 'fulfillment'::text)
#  idx_jrc_crm_backoffice_queue                           (account_id,status,stage)
#  index_jrc_crm_backoffice_requests_on_account_id        (account_id)
#  index_jrc_crm_backoffice_requests_on_business_unit_id  (business_unit_id)
#  index_jrc_crm_backoffice_requests_on_contact_id        (contact_id)
#  index_jrc_crm_backoffice_requests_on_contract_id       (contract_id)
#  index_jrc_crm_backoffice_requests_on_owner_id          (owner_id)
#  index_jrc_crm_backoffice_requests_on_requested_by_id   (requested_by_id)
#  index_jrc_crm_backoffice_requests_on_sales_order_id    (sales_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (contract_id => jrc_crm_contracts.id)
#  fk_rails_...  (owner_id => users.id)
#  fk_rails_...  (requested_by_id => users.id)
#  fk_rails_...  (sales_order_id => jrc_crm_sales_orders.id)
#
module JrcCrm
  class BackofficeRequest < ApplicationRecord
    self.table_name = 'jrc_crm_backoffice_requests'

    STAGES = %w[request analysis documentation contract implementation provisioning finance issues approval completed].freeze
    ACTIVE_STATUSES = %w[pending in_progress waiting_customer blocked].freeze

    belongs_to :account
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :sales_order, class_name: 'JrcCrm::SalesOrder'
    belongs_to :contract, class_name: 'JrcCrm::Contract', optional: true
    belongs_to :contact, optional: true
    belongs_to :owner, class_name: 'User'
    belongs_to :requested_by, class_name: 'User'
    belongs_to :operations_queue, class_name: 'JrcOperations::Queue', optional: true
    belongs_to :operations_sla_policy, class_name: 'JrcOperations::SlaPolicy', optional: true
    has_many_attached :documents

    enum request_kind: { fulfillment: 'fulfillment', approval: 'approval', change: 'change', cancellation: 'cancellation' }
    enum status: { pending: 'pending', in_progress: 'in_progress', waiting_customer: 'waiting_customer', blocked: 'blocked',
                   approved: 'approved', rejected: 'rejected', canceled: 'canceled', completed: 'completed' }
    enum priority: { low: 'low', normal: 'normal', high: 'high', critical: 'critical' }

    validates :request_number, :title, presence: true
    validates :operations_queue, :operations_sla_policy, presence: true, on: :create
    validates :stage, inclusion: { in: STAGES }
    validates :request_number, uniqueness: { scope: :account_id }
    validates :sales_order_id, uniqueness: { scope: %i[account_id request_kind] }, if: :fulfillment?
    validate :associations_belong_to_account
    before_validation :assign_number, on: :create
    after_update :sync_sla_status, if: :saved_change_to_status?
    after_save :audit_assignment, if: -> { saved_change_to_owner_id? || saved_change_to_operations_queue_id? }

    def advance!
      validate_stage_dependencies!
      previous_status = status
      target = next_applicable_stage
      update!(stage: target, status: target == 'completed' ? 'completed' : 'in_progress',
              completed_at: target == 'completed' ? Time.current : nil)
      clock = JrcOperations::SlaClock.new(self)
      clock.status_changed!(from: previous_status, to: status) if previous_status != status
      clock.stage_changed! if previous_changes['stage'].present?
      if target == 'finance' && previous_changes['stage']&.first == 'provisioning'
        JrcCrm::OrderWorkflowSyncService.new(order: sales_order, actor: owner, event: 'implementation_completed').call
      end
      self
    end

    def next_applicable_stage
      candidates = case stage
                   when 'request' then %w[analysis]
                   when 'analysis' then %w[documentation contract implementation provisioning finance completed]
                   when 'documentation' then %w[contract implementation provisioning finance completed]
                   when 'contract' then %w[implementation provisioning finance completed]
                   when 'implementation' then %w[provisioning finance completed]
                   when 'provisioning' then %w[finance completed]
                   when 'finance' then %w[issues approval completed]
                   when 'issues' then %w[approval completed]
                   when 'approval' then %w[completed]
                   else %w[completed]
                   end
      candidates.find { |candidate| stage_applicable?(candidate) } || 'completed'
    end

    def stage_applicable?(candidate)
      data = (metadata || {}).with_indifferent_access
      snap = (sales_order.snapshot || {}).with_indifferent_access
      case candidate
      when 'documentation' then required_documents.any? || documents.attached?
      when 'contract' then contract.present? || bool(data[:contract_required])
      when 'implementation' then bool(data[:implementation_required]) || bool(snap[:send_to_implementation]) || Array(snap[:checklist]).any?
      when 'provisioning' then bool(data[:provisioning_required]) || bool(snap[:requires_provisioning])
      when 'finance' then bool(data.fetch(:finance_required, true)) || sales_order.invoices.exists?
      when 'issues' then open_issues.any?
      when 'approval' then request_kind.in?(%w[approval change cancellation]) || bool(data[:approval_required])
      else true
      end
    end

    def document_requirements
      data = (metadata || {}).with_indifferent_access
      configured = Array(data[:document_requirements]).filter_map do |raw|
        row = raw.respond_to?(:to_h) ? raw.to_h.with_indifferent_access : { label: raw.to_s }
        next unless document_requirement_matches?(row[:conditions])

        {
          'key' => row[:key].presence || row[:label].to_s.parameterize,
          'label' => row[:label].presence || row[:name].presence || row[:key].to_s.humanize,
          'required' => row.key?(:required) ? bool(row[:required]) : true,
          'blocking' => row.key?(:blocking) ? bool(row[:blocking]) : true,
          'conditional' => row[:conditions].present?,
          'conditions' => row[:conditions] || {}
        }
      end
      legacy = Array(data[:required_documents]).map do |name|
        { 'key' => name.to_s.parameterize, 'label' => name.to_s, 'required' => true, 'blocking' => true,
          'conditional' => false, 'conditions' => {} }
      end
      (configured + legacy).uniq { |row| row['key'] }
    end

    def required_documents
      document_requirements.select { |row| row['required'] }.map { |row| row['label'] }
    end

    def blocking_document_requirements
      document_requirements.select { |row| row['required'] && row['blocking'] }
    end

    def open_issues
      Array((metadata || {})['issues']).reject do |issue|
        %w[resolved canceled].include?((issue['status'] || issue[:status]).to_s)
      end
    end

    def blocking_open_issues
      open_issues.select do |issue|
        issue = issue.with_indifferent_access
        issue.key?(:blocking) ? bool(issue[:blocking]) : true
      end
    end

    private

    def audit_assignment
      JrcCrm::AuditEvent.create!(account_id: account_id, actor_type: 'System',
        event_type: previously_new_record? ? 'operations_assigned' : 'operations_transferred',
        resource_type: 'JrcCrm::BackofficeRequest', resource_id: id,
        from_value: { owner_id: owner_id_before_last_save, queue_id: operations_queue_id_before_last_save },
        to_value: { owner_id: owner_id, queue_id: operations_queue_id }, metadata: { source: 'jrc_operations_routing' })
    end

    def sync_sla_status
      from, to = saved_change_to_status
      JrcOperations::SlaClock.new(self).status_changed!(from: from, to: to)
    end

    def validate_stage_dependencies!
      errors = []
      data = (metadata || {}).with_indifferent_access
      snap = (sales_order.snapshot || {}).with_indifferent_access

      if stage.in?(%w[request analysis]) && !sales_order.status.in?(%w[approved separating invoiced shipped completed])
        errors << 'O pedido precisa estar aprovado antes de iniciar o fluxo operacional.'
      end

      if stage == 'documentation'
        statuses = (data[:document_statuses] || {}).with_indifferent_access
        pending = blocking_document_requirements.reject do |requirement|
          statuses[requirement['key']].to_s == 'approved' || statuses[requirement['label']].to_s == 'approved'
        end
        errors << "Documentos obrigatórios pendentes: #{pending.map { |row| row['label'] }.join(', ')}" if pending.any?
      end

      if stage == 'contract' && stage_applicable?('contract')
        errors << 'O contrato precisa estar assinado antes da implantação.' unless contract&.signature_status == 'signed'
      end

      if stage == 'implementation' && stage_applicable?('implementation')
        checklist = Array(data[:implementation_checklist].presence || snap[:checklist])
        pending = checklist.reject { |item| bool(item['done'] || item[:done]) }
        errors << 'Existem itens pendentes no checklist de implantação.' if checklist.any? && pending.any?
      end

      if stage == 'provisioning' && stage_applicable?('provisioning')
        completed = data[:provisioning_completed_at].present?
        mode = data[:provisioning_completion_mode].to_s
        errors << 'O provisionamento ainda não possui execução confirmada. Integrações não configuradas não são concluídas automaticamente.' unless completed && %w[manual external].include?(mode)
      end

      if blocking_open_issues.any?
        errors << 'Resolva as pendências bloqueantes antes de concluir o fluxo.'
      end

      if stage == 'approval' && stage_applicable?('approval')
        errors << 'A aprovacao explicita do administrador esta pendente.' unless data.dig(:approval_decision, :status) == 'approved'
      end

      if stage == 'finance' && bool(data[:payment_required_before_completion])
        errors << 'Há faturamento/recebimento pendente.' unless sales_order.invoices.any?(&:paid?)
      end

      if errors.any?
        errors.each { |message| self.errors.add(:base, message) }
        raise ActiveRecord::RecordInvalid.new(self)
      end
    end

    def document_requirement_matches?(conditions)
      rules = (conditions || {}).with_indifferent_access
      return true if rules.blank?

      snap = (sales_order.snapshot || {}).with_indifferent_access
      product_ids = sales_order.order_items.map(&:product_id).compact.map(&:to_i)
      checks = []
      checks << Array(rules[:order_origins]).map(&:to_s).include?(sales_order.order_origin.to_s) if rules[:order_origins].present?
      checks << Array(rules[:request_kinds]).map(&:to_s).include?(request_kind.to_s) if rules[:request_kinds].present?
      checks << Array(rules[:priorities]).map(&:to_s).include?(priority.to_s) if rules[:priorities].present?
      checks << Array(rules[:product_ids]).map(&:to_i).intersect?(product_ids) if rules[:product_ids].present?
      checks << Array(rules[:business_unit_ids]).map(&:to_i).include?(sales_order.business_unit_id.to_i) if rules[:business_unit_ids].present?
      if rules[:snapshot].present?
        checks << rules[:snapshot].all? { |key, value| snap[key].to_s == value.to_s }
      end
      checks.all?
    end

    def bool(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def assign_number
      self.request_number ||= "BKO-#{Time.zone.today.year}-#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
    end

    def associations_belong_to_account
      errors.add(:sales_order, 'must belong to account') if sales_order && sales_order.account_id != account_id
      errors.add(:contract, 'must belong to account') if contract && contract.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
      errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id)
      errors.add(:requested_by, 'must belong to account') if requested_by && !account.users.exists?(requested_by.id)
      errors.add(:operations_queue, 'must belong to account') if operations_queue && operations_queue.account_id != account_id
      errors.add(:operations_sla_policy, 'must belong to account') if operations_sla_policy && operations_sla_policy.account_id != account_id
    end
  end
end
