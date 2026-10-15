class JrcFlowEffects::Authority
  attr_reader :account, :user

  def initialize(account:, user:, access_token:)
    @account_id = account.id
    @user_id = user&.id
    @token_id = access_token&.id
    @token = access_token&.token
  end

  def authorize!(lock: false)
    raise Pundit::NotAuthorizedError unless [@user_id, @token_id, @token].all?

    @account = scope(Account, lock).find(@account_id)
    @user = scope(User, lock).find(@user_id)
    membership = scope(AccountUser, lock).find_by(account_id: @account_id, user_id: @user_id)
    token = scope(AccessToken, lock).find_by(id: @token_id, token: @token, owner_type: 'User', owner_id: @user_id)
    raise Pundit::NotAuthorizedError unless token && membership&.administrator? && active_identity?

    self
  end

  private

  def active_identity?
    @account.active? && @account.api_and_webhooks_enabled? && @user.active_for_authentication? && @user.confirmed?
  end

  def scope(model, lock)
    lock ? model.lock('FOR SHARE') : model.all
  end
end
