# frozen_string_literal: true

class JrcContactCenter::Case < JrcContactCenter::ApplicationRecord
  PRIORITIES = %w[low normal high urgent].freeze
  STATUSES = %w[open in_progress waiting resolved closed canceled].freeze

  belongs_to :contact, optional: true
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession', optional: true
  belongs_to :owner_account_user, class_name: 'AccountUser', optional: true
  belongs_to :unit, class_name: 'JrcContactCenter::Unit', optional: true
  belongs_to :queue, class_name: 'JrcContactCenter::Queue', optional: true
  has_many :events, class_name: 'JrcContactCenter::CaseEvent', dependent: :restrict_with_error

  validates :protocol, :channel, :category, :summary, presence: true
  validates :protocol, uniqueness: { scope: :account_id }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :status, inclusion: { in: STATUSES }
end
