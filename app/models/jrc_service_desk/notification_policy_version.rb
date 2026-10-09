# frozen_string_literal: true

class JrcServiceDesk::NotificationPolicyVersion < JrcServiceDesk::UnitRecord
  include JrcServiceDesk::AppendOnly
  belongs_to :published_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :inbox, optional: true
  belongs_to :ticket_type, class_name: 'JrcServiceDesk::TicketType', optional: true
  belongs_to :service, class_name: 'JrcServiceDesk::Service', optional: true
  validates :event_type, inclusion: { in: JrcServiceDesk::NotificationEvent::TYPES }
  validates :channel, inclusion: { in: %w[email whatsapp] }
  validates :version, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: %i[account_id unit_id event_type channel ticket_type_id service_id] }
  validates :template, presence: true, length: { maximum: 10_000 }
  validates :template_version, presence: true, length: { maximum: 80 }
  validates :digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :references_are_consistent

  private

  def references_are_consistent
    validate_unit_reference(:published_by_membership)
    %i[ticket_type service].each do |name|
      validate_unit_reference(name)
      validate_active_reference(name) if enabled?
    end
    validate_account_reference(:inbox)
    errors.add(:inbox, 'is required for enabled notifications') if enabled? && inbox.nil?
    unknown = template.to_s.scan(/\{\{(.*?)\}\}/).flatten - JrcServiceDesk::NotificationSource::FIELDS
    errors.add(:template, 'has unsupported fields') if unknown.any?
  end
end
