class JrcFlowNativeConfiguration < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  scope :current, -> { where('expires_at > clock_timestamp()') }
end
