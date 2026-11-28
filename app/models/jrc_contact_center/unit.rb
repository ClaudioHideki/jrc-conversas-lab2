# frozen_string_literal: true

class JrcContactCenter::Unit < JrcContactCenter::ApplicationRecord
  include JrcContactCenter::AdministrativeAuditable
  KINDS = %w[sac finance coe administrative].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :parent_unit, class_name: 'JrcContactCenter::Unit', optional: true
  has_many :child_units, class_name: 'JrcContactCenter::Unit', foreign_key: :parent_unit_id, inverse_of: :parent_unit, dependent: :restrict_with_error
  has_many :queues, class_name: 'JrcContactCenter::Queue', dependent: :restrict_with_error

  validates :code, :name, presence: true
  validates :code, uniqueness: { scope: :account_id }, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :timezone, presence: true
  validate :known_timezone
  validate :corporate_links
  validate :native_calendar_catalog
  validate :native_recording_policy_draft

  private

  def native_recording_policy_draft
    key = JrcContactCenter::RecordingPolicyDraft::KEY
    previous = new_record? ? {} : settings_in_database
    return unless settings.key?(key) || previous.key?(key)

    raise JrcContactCenter::OperationError, 'recording_policy_requires_existing_unit' unless persisted? && settings.key?(key)

    definition = JrcContactCenter::RecordingPolicyDraft.stored(self)
    JrcContactCenter::RecordingPolicyDraft.authorize_queues!(unit: self, definition: definition, scope: queues)
  rescue JrcContactCenter::OperationError, ArgumentError, KeyError, ActiveRecord::RecordNotFound
    errors.add(:settings, JrcContactCenter::RecordingPolicyDraft::ERROR)
  end

  def native_calendar_catalog
    key = JrcContactCenter::CalendarCatalogState::KEY
    previous = new_record? ? {} : settings_in_database
    return unless settings.key?(key) || previous.key?(key)

    valid = !new_record? && settings.key?(key)
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_catalog' unless valid

    JrcContactCenter::CalendarCatalogState.new(unit: self).call
  rescue JrcContactCenter::OperationError
    errors.add(:settings, 'invalid_contact_center_calendar_catalog')
  end

  def corporate_links
    return if settings['issuer_company_id'].blank? && settings['business_unit_id'].blank?

    JrcApprovals::Authorization.scope!(account, settings['issuer_company_id'].presence, settings['business_unit_id'].presence)
  rescue ActiveRecord::RecordNotFound, JrcApprovals::Error
    errors.add(:settings, 'invalid_corporate_scope')
  end

  def known_timezone
    errors.add(:timezone, 'is invalid') unless Time.find_zone(timezone)
  end
end
