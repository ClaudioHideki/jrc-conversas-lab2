# frozen_string_literal: true

require 'digest'

# Separate from the historical operator state version; clocks and drafts do not enter this token.
class JrcContactCenter::DeferredPauseRevision
  def self.token(account:, member:)
    raise ActiveRecord::RecordNotFound unless member.account_id == account.id

    row = JrcContactCenter::DeferredPauseRequest.where(account: account, account_user: member).order(id: :desc).first
    Digest::SHA256.hexdigest(['jrc_cc_deferred_pause_revision_v1', account.id, member.id, row&.id, row&.state].to_json)
  end

  def self.check!(account:, member:, expected:)
    return if token(account: account, member: member) == expected

    raise JrcContactCenter::OperationError.new('stale_pause_request', status: :conflict)
  end
end
