class JrcFlowNativeRegistration < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  belongs_to :account_user, optional: true
  has_many :bindings, class_name: 'JrcFlowNativeBinding', foreign_key: :registration_id, dependent: :restrict_with_exception
  has_many :session_handles, class_name: 'JrcFlowNativeSessionHandle', foreign_key: :registration_id, dependent: :restrict_with_exception
  scope :current, -> { where(state: 'ACTIVE').where('expires_at > clock_timestamp() AND credential_expires_at > clock_timestamp()') }
end
