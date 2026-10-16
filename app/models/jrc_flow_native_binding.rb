class JrcFlowNativeBinding < ApplicationRecord
  belongs_to :registration, class_name: 'JrcFlowNativeRegistration'
  belongs_to :account
  belongs_to :inbox
end
