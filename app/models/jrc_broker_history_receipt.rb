class JrcBrokerHistoryReceipt < ApplicationRecord
  self.filter_attributes += [:origin_context]
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact
  belongs_to :conversation
  belongs_to :message, optional: true

  def readonly?
    persisted?
  end
end
