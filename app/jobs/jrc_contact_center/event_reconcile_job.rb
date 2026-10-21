# frozen_string_literal: true

class JrcContactCenter::EventReconcileJob < ApplicationJob
  queue_as :default

  def perform(account_id, event_id)
    account = Account.find(account_id)
    return unless account.feature_enabled?('jrc_contact_center')

    event = JrcContactCenter::EventInbox.where(account: account).find(event_id)
    JrcContactCenter::EventReconciler.new(event_record: event).call
  end
end
