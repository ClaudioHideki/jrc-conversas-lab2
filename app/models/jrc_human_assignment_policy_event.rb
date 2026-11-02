class JrcHumanAssignmentPolicyEvent < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :user, optional: true
end
