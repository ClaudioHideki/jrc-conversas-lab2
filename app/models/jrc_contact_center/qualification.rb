# frozen_string_literal: true

class JrcContactCenter::Qualification < JrcContactCenter::ApplicationRecord
  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession', optional: true
  belongs_to :conversation, optional: true
  belongs_to :account_user

  scope :pending, -> { where(completed_at: nil) }
  validates :channel, inclusion: { in: %w[voice whatsapp] }
  validates :outcome_code, presence: true, length: { maximum: 100 }, if: :completed_at?
  validates :reason_code, presence: true, length: { maximum: 100 }, if: -> { started_at && completed_at }
  validates :notes, length: { maximum: 4000 }
  validates :account_user_id, uniqueness: { scope: %i[account_id call_session_id] }, if: :call_session_id?
  validates :account_user_id, uniqueness: { scope: %i[account_id conversation_id conversation_cycle] }, if: :conversation_id?
  validate :account_and_target_match

  def elapsed_seconds
    duration_seconds || [(Time.current - started_at).to_i, 0].max
  end

  def refresh_overdue!
    return self if completed_at || !started_at || elapsed_seconds < acw_limit_seconds

    update_columns(overdue: true, exceeded_seconds: [elapsed_seconds - acw_limit_seconds, 0].max, updated_at: Time.current)
    self
  end

  def operational_payload
    refresh_overdue!
    as_json(only: %i[id account_id account_user_id channel call_session_id conversation_id conversation_cycle reason_code outcome_code notes
                    started_at completed_at acw_limit_seconds duration_seconds overdue exceeded_seconds created_at updated_at])
      .merge('elapsed_seconds' => started_at ? elapsed_seconds : nil, 'agent_name' => account_user.user.available_name,
             'conversation_display_id' => conversation&.display_id,
             'attendance_seconds' => call_session&.answered_at && call_session.ended_at ? (call_session.ended_at - call_session.answered_at).to_i : nil)
  end

  private

  def account_and_target_match
    target = channel == 'voice' ? call_session : conversation
    errors.add(:base, 'account_target_mismatch') unless target&.account_id == account_id && account_user&.account_id == account_id
  end
end
