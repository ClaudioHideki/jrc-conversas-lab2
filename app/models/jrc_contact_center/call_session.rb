# frozen_string_literal: true

class JrcContactCenter::CallSession < JrcContactCenter::ApplicationRecord
  DIRECTIONS = %w[inbound outbound].freeze
  STATUSES = %w[created ringing queued connected held transferring ended failed].freeze

  belongs_to :contact, optional: true
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  belongs_to :current_unit, class_name: 'JrcContactCenter::Unit', optional: true
  belongs_to :current_queue, class_name: 'JrcContactCenter::Queue', optional: true
  has_many :legs, class_name: 'JrcContactCenter::CallLeg', dependent: :restrict_with_error
  has_many :ivr_events, class_name: 'JrcContactCenter::IvrEvent', dependent: :restrict_with_error
  has_many :fallback_events, class_name: 'JrcContactCenter::FallbackEvent', dependent: :restrict_with_error

  validates :provider, :correlation_id, :started_at, presence: true
  validates :correlation_id, uniqueness: { scope: :account_id }
  validates :external_session_id, uniqueness: { scope: %i[account_id provider], allow_nil: true }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :status, inclusion: { in: STATUSES }
  validate :timestamps_are_monotonic
  after_update :track_closure_survey
  after_update :ensure_operational_tabulation
  after_update_commit :enqueue_closure_survey

  def f1_data
    metadata.fetch('jrc_f1', {})
  end

  def update_f1_data(attributes)
    update!(metadata: metadata.merge('jrc_f1' => f1_data.merge(attributes)))
  end

  private

  def ensure_operational_tabulation
    return unless saved_change_to_status? || saved_change_to_answered_at? || saved_change_to_ended_at?

    JrcContactCenter::QualificationManager.ensure_voice!(self)
  end

  def track_closure_survey
    @closure_survey_pending = true if saved_change_to_status? || saved_change_to_answered_at? || saved_change_to_ended_at?
  end

  def enqueue_closure_survey
    return unless @closure_survey_pending

    @closure_survey_pending = false
    return unless eligible_for_closure_survey?
    return unless JrcRelationship::SurveyRule.where(account: account, active: true).exists?(["matchers ->> 'source_type' = ?", self.class.name])

    JrcRelationship::SurveyClosureJob.perform_later(self.class.name, id, "contact-center:#{id}")
  end

  def eligible_for_closure_survey?
    status == 'ended' && answered_at && ended_at && account.feature_enabled?('jrc_contact_center') &&
      JrcRelationship::SurveyEngine.enabled?(account)
  end

  def timestamps_are_monotonic
    errors.add(:answered_at, 'must not be before started_at') if precedes?(answered_at, started_at)
    errors.add(:ended_at, 'must not be before started_at') if precedes?(ended_at, started_at)
    errors.add(:ended_at, 'must not be before answered_at') if answered_at && precedes?(ended_at, answered_at)
  end

  def precedes?(timestamp, lower_bound)
    timestamp && timestamp < lower_bound
  end
end
