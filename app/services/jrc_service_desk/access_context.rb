# frozen_string_literal: true

# Only accepts the trusted context produced by the native authentication helpers.
# Never construct this context from request parameters or an external identity.
# Availability is a prerequisite, NOT an operational permission or a row-level ACL.
class JrcServiceDesk::AccessContext
  attr_reader :account, :user, :account_user

  def initialize(user_context)
    @account = user_context[:account]
    @user = user_context[:user]
    @account_user = user_context[:account_user]
  end

  def available?
    return false unless account && user && account_user
    return false unless account.persisted? && user.persisted? && account_user.persisted?
    return false unless account.id && user.id
    return false unless account_user.account_id == account.id && account_user.user_id == user.id

    account.active? && account.feature_enabled?(::JrcServiceDesk::FEATURE_FLAG) == true
  end

  # Even a matching account never grants an action without a concrete policy.
  def record_in_account?(record)
    available? && record.respond_to?(:account_id) && record.account_id == account.id
  end
end
