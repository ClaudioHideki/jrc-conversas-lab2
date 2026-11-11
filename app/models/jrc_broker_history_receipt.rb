class JrcBrokerHistoryReceipt < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact
  belongs_to :conversation
  belongs_to :message, optional: true

  def readonly?
    persisted?
  end
end
