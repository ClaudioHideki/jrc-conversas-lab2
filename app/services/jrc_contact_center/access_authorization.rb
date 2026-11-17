class JrcContactCenter::AccessAuthorization
  def initialize(context:)
    @context = context
    @account = context.fetch(:account)
    @actor = context.fetch(:account_user)
    @user = context.fetch(:user)
  end

  def authorize!
    return if @user.is_a?(SuperAdmin)

    policy = JrcContactCenter::ModulePolicy.new(@context, :contact_center)
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: @user)
    allowed = @actor.administrator? && policy.administer? && (!coverage.configured? || coverage.group?)
    raise Pundit::NotAuthorizedError unless allowed
  end

  def grant_for(subject)
    raise ActiveRecord::RecordNotFound unless subject.account_id == @account.id

    key = subject.is_a?(AccountUser) ? :account_user : :team
    JrcContactCenter::AccessGrant.find_or_initialize_by(account: @account, key => subject)
  end

  def revision(subject, grant)
    identity = subject.is_a?(AccountUser) ? subject.attributes.slice('id', 'account_id', 'user_id', 'role', 'custom_role_id') : subject.attributes
    state = [identity, JrcContactCenter::ConfigurationRevision.token(grant)]
    if subject.is_a?(AccountUser)
      state << subject.custom_role&.attributes
      team_ids = Team.where(account: @account).joins(:team_members).where(team_members: { user_id: subject.user_id }).select(:id)
      state << JrcContactCenter::AccessGrant.where(account: @account, team_id: team_ids).order(:id).map(&:attributes)
    else
      state << subject.team_members.order(:user_id).pluck(:user_id)
    end
    Digest::SHA256.hexdigest(state.to_json)
  end

  def update!(subject:, attributes:, expected:)
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @actor) do
      authorize!
      subject.reload
      grant = grant_for(subject)
      check_revision!(subject, grant, expected)
      previous = subject.is_a?(AccountUser) ? effective(subject) : grant.allowed
      grant.assign_attributes(attributes)
      proposed = subject.is_a?(AccountUser) ? effective(subject, preview: grant) : grant.allowed
      JrcContactCenter::GrantGuard.check!(actor: @user, account: @account, proposed: proposed, previous: previous)
      grant.save!
      grant
    end
  end

  def effective(member, preview: nil)
    context = { account: @account, account_user: member, user: member.user }
    context[:cc_access_preview] = preview if preview
    JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
  end

  private

  def check_revision!(subject, grant, expected)
    unless expected.is_a?(String) && expected.present?
      raise JrcContactCenter::OperationError.new('configuration_revision_required', status: :precondition_required)
    end
    return if ActiveSupport::SecurityUtils.secure_compare(revision(subject, grant), expected)

    raise JrcContactCenter::OperationError.new('stale_configuration_revision', status: :conflict)
  end
end
