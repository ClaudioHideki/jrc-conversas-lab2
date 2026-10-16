class JrcFlowOwnershipScope < ApplicationRecord
  has_many :epochs, class_name: 'JrcFlowOwnershipEpoch', foreign_key: :scope_id, dependent: :restrict_with_exception
end
