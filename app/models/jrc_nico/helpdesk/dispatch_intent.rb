# frozen_string_literal: true

# Technical enqueue intent, never a business approval, action receipt or grant.
# Only current native Capture creates it. Historical Events are not backfilled.
class JrcNico::Helpdesk::DispatchIntent < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_dispatch_intents'
  belongs_to :account
  belongs_to :event, class_name: 'JrcNico::Helpdesk::Event'
  attr_readonly :account_id, :event_id, :created_at
  validates :event_id, uniqueness: true
  validate :scope_integrity
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Native delivery intent identity is immutable' }
  before_destroy { throw :abort }
  after_create_commit :dispatch_after_commit

  private

  def scope_integrity
    errors.add(:account, 'scope mismatch') unless event&.account_id == account_id
  end

  def dispatch_after_commit
    JrcNico::Helpdesk::EventDispatch.call(event)
  end
end
