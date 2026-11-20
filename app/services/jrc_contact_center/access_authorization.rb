class JrcContactCenter::AccessAuthorization
  attr_reader :account, :user

  def initialize(context:)
    @context = context
    @account = context.fetch(:account)
    @actor = context.fetch(:account_user)
    @user = context.fetch(:user)
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless @user.reload.active_for_authentication?

    return if @user.is_a?(SuperAdmin)

    policy = JrcContactCenter::ModulePolicy.new(@context, :contact_center)
    coverage = JrcContactCenter::CorporateCoverage.new(account: @account, user: @user)
    allowed = @actor.administrator? && policy.administer? && (!coverage.configured? || coverage.group?)
    raise Pundit::NotAuthorizedError unless allowed
  end

  def grant_for(subject)
    raise ActiveRecord::RecordNotFound unless subject.account_id == @account.id

    key = subject.is_a?(AccountUser) ? :account_user : :team
    attributes = { account: @account }
    attributes[key] = subject
    JrcContactCenter::AccessGrant.find_or_initialize_by(attributes)
  end

  def revision(subject, grant)
    state = native_revision_state(subject, grant)
    ids = subject.is_a?(AccountUser) ? source_team_ids(subject) : [subject.id]
    sources = JrcContactCenter::TeamState.where(account: @account, team_id: ids).order(:team_id).map(&:attributes)
    state << { 'cc_team_states_v1' => sources } if sources.any?
    Digest::SHA256.hexdigest(state.to_json)
  end

  def update!(subject:, attributes:, expected:, confirmation: nil)
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @actor) do
      authorize!
      subject.reload
      grant = grant_for(subject)
      check_revision!(subject, grant, expected)
      values = attributes.symbolize_keys
      change = activity_change(subject, values, expected)
      previous = { allowed: grant.allowed.dup, effective: subject.is_a?(AccountUser) ? effective(subject) : [] }
      grant.assign_attributes(values.except(:active))
      check_grant_effects!(subject, grant, previous, change&.preview || {})
      change&.check!(confirmation: confirmation)
      grant.save!
      change&.save!
      grant
    end
  end

  def effective(member, preview: nil, team_preview: nil, activity: {})
    context = { account: @account, account_user: member, user: member.user }
    context[:cc_team_activity_preview] = activity
    context[:cc_access_preview] = preview if preview
    context[:cc_team_access_preview] = team_preview if team_preview
    JrcContactCenter::ModulePolicy.new(context, :contact_center).effective_permissions
  end

  private

  def native_revision_state(subject, grant)
    identity = subject.is_a?(AccountUser) ? subject.attributes.slice('id', 'account_id', 'user_id', 'role', 'custom_role_id') : subject.attributes
    state = [identity, JrcContactCenter::ConfigurationRevision.token(grant)]
    if subject.is_a?(AccountUser)
      state << subject.custom_role&.attributes
      team_ids = Team.where(account: @account).joins(:team_members).where(team_members: { user_id: subject.user_id }).select(:id)
      state << JrcContactCenter::AccessGrant.where(account: @account, team_id: team_ids).order(:id).map(&:attributes)
    else
      state << subject.team_members.order(:user_id).pluck(:user_id)
    end
    state
  end

  def source_team_ids(subject)
    Team.where(account: @account).joins(:team_members).where(team_members: { user_id: subject.user_id }).select(:id)
  end

  def activity_change(subject, attributes, revision)
    return unless attributes.key?(:active)
    raise JrcContactCenter::OperationError, 'invalid_access_authorization' unless subject.is_a?(Team)

    JrcContactCenter::TeamActivityChange.new(account: @account, actor: @actor, team: subject, active: attributes[:active], revision: revision)
  end

  def check_grant_effects!(subject, grant, previous, activity)
    if subject.is_a?(AccountUser)
      JrcContactCenter::GrantGuard.check!(actor: @user, account: @account, proposed: grant.allowed, previous: previous[:allowed])
      proposed = effective(subject, preview: grant)
      JrcContactCenter::GrantGuard.check!(actor: @user, account: @account, proposed: proposed, previous: previous[:effective])
    else
      JrcContactCenter::TeamGrantEffects.new(
        authority: self, team: subject, grant: grant, previous: previous[:allowed], activity: activity
      ).check!
    end
  end

  def check_revision!(subject, grant, expected)
    unless expected.is_a?(String) && expected.present?
      raise JrcContactCenter::OperationError.new('configuration_revision_required', status: :precondition_required)
    end
    return if ActiveSupport::SecurityUtils.secure_compare(revision(subject, grant), expected)

    raise JrcContactCenter::OperationError.new('stale_configuration_revision', status: :conflict)
  end
end
