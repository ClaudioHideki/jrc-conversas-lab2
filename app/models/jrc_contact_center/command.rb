# frozen_string_literal: true

class JrcContactCenter::Command < JrcContactCenter::ApplicationRecord
  STATUSES = %w[requested accepted_by_gateway confirmed_by_pabx rejected unknown].freeze

  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession', optional: true
  belongs_to :actor_account_user, class_name: 'AccountUser'

  validates :command_id, :action, :requested_at, presence: true
  validates :command_id, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: STATUSES }
end
