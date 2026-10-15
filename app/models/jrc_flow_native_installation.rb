class JrcFlowNativeInstallation < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  belongs_to :registration, class_name: 'JrcFlowNativeRegistration'
end
