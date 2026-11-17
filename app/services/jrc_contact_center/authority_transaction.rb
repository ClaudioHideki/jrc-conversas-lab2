class JrcContactCenter::AuthorityTransaction
  def self.call(account:, member:)
    AccountUser.uncached do
      account.with_lock do
        member&.reload
        raise Pundit::NotAuthorizedError unless account.active?

        yield
      end
    end
  end
end
