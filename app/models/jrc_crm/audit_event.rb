# == Schema Information
#
# Table name: jrc_crm_audit_events
#
#  id                            :bigint           not null, primary key
#  actor_type                    :string
#  event_type                    :string
#  from_value                    :jsonb
#  ip_address                    :string
#  metadata                      :jsonb
#  resource_type                 :string
#  to_value                      :jsonb
#  created_at                    :datetime         not null
#  account_id                    :integer          not null
#  actor_id                      :integer
#  legacy_sales_stage_history_id :bigint
#  resource_id                   :bigint
#
# Indexes
#
#  idx_jrc_crm_audits_legacy_sales                              (account_id,legacy_sales_stage_history_id) UNIQUE WHERE (legacy_sales_stage_history_id IS NOT NULL)
#  index_jrc_crm_audit_events_on_account_id                     (account_id)
#  index_jrc_crm_audit_events_on_actor_id                       (actor_id)
#  index_jrc_crm_audit_events_on_created_at                     (created_at)
#  index_jrc_crm_audit_events_on_event_type                     (event_type)
#  index_jrc_crm_audit_events_on_resource_type_and_resource_id  (resource_type,resource_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
module JrcCrm
  class AuditEvent < ApplicationRecord
    self.table_name = 'jrc_crm_audit_events'
    
    belongs_to :account
    
    validates :event_type, :resource_type, :resource_id, presence: true
    
    EVENT_TYPES = %w[lead_deleted commission_calculation_pending backoffice_payment_gate_pending lead_created lead_updated lead_converted deal_created deal_updated deal_stage_changed deal_owner_changed deal_won deal_lost activity_created activity_completed proposal_created proposal_sent proposal_viewed proposal_accepted proposal_rejected commission_created commission_updated commission_status_changed backoffice_created backoffice_updated backoffice_stage_changed backoffice_document_uploaded backoffice_document_status_changed backoffice_issue_created backoffice_issue_resolved backoffice_provisioning_confirmed backoffice_reopened order_attachment_uploaded contract_created contract_updated contract_document_uploaded contract_signature_prepared contract_signature_sent contract_manual_signature_registered contract_renewed contract_addendum_created customer_company_created customer_company_updated customer_contact_linked customer_contact_updated customer_contact_merged customer_address_changed customer_contact_point_changed customer_import_applied customer_operations_backfilled]
    validates :event_type, inclusion: { in: EVENT_TYPES }
    
    scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
    scope :recent, -> { order(created_at: :desc) }
  end
end
