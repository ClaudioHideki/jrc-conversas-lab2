# frozen_string_literal: true

# Dedicated worker boundary, not a new authorization policy. The caller must
# reauthorize the attested original actor and each destination inside the block.
# NO KEY UPDATE still serializes native Account FOR UPDATE authority writers,
# while permitting native destination inserts' Account foreign-key KEY SHARE.
class JrcContactCenter::EndingActions::ExecutionTransaction
  def self.call(account:)
    if Account.connection.transaction_open?
      raise JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction'
    end

    AccountUser.uncached do
      account.with_lock('FOR NO KEY UPDATE') do
        raise Pundit::NotAuthorizedError unless account.active?

        yield
      end
    end
  end
end
