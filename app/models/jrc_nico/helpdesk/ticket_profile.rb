class JrcNico::Helpdesk::TicketProfile < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_ticket_profiles'
  belongs_to :account
  belongs_to :unit, class_name: 'JrcServiceDesk::Unit'
  belongs_to :ticket, class_name: 'JrcServiceDesk::Ticket'
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  validates :ticket_id, uniqueness: true
  validates :case_kind, inclusion: { in: %w[defect request complaint legal commercial] }, allow_nil: true
  validates :defect_key, length: { maximum: 120 }, format: { with: /\A[a-zA-Z0-9_.:-]+\z/ }, allow_nil: true
  validate :scope_integrity, :linked_scope, :activity_date

  private

  def scope_integrity
    errors.add(:ticket, 'outside scope') unless ticket&.account_id == account_id && ticket.unit_id == unit_id && ticket.company_id == company_id
  end

  def linked_scope
    errors.add(:unit, 'outside account') unless unit&.account_id == account_id
    errors.add(:company, 'outside account') if company && company.account_id != account_id
  end

  def activity_date
    errors.add(:last_relevant_at, 'cannot be in the future') if last_relevant_at && last_relevant_at > Time.current
  end
end
