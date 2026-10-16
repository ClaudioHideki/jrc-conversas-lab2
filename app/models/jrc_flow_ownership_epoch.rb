class JrcFlowOwnershipEpoch < ApplicationRecord
  self.table_name = 'jrc_flow_ownership_epochs'

  belongs_to :scope, class_name: 'JrcFlowOwnershipScope'
  belongs_to :registration, class_name: 'JrcFlowNativeRegistration'
end
