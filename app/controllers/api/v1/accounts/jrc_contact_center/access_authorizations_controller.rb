class Api::V1::Accounts::JrcContactCenter::AccessAuthorizationsController < Api::V1::Accounts::JrcContactCenter::BaseController
  rescue_from JrcContactCenter::TeamRosterWithdrawalReview::Required, with: :render_team_activity_review

  before_action -> { authority.authorize! }
  before_action -> { response.headers['Cache-Control'] = 'no-store' }

  def index
    params[:page] = 1 if params[:page].blank?
    relation = filter_status(subjects)
    if params[:q].present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(100))}%"
      relation = users? ? relation.joins(:user).where('users.name ILIKE ?', pattern) : relation.where('teams.name ILIKE ?', pattern)
    end
    render json: list_payload(relation.order(:id)) { |subject| present(subject) }
  end

  def show
    render json: base_payload.merge(item: present(subjects.find(params[:id])))
  end

  def update
    subject = subjects.find(params[:id])
    authority.update!(subject: subject, attributes: access_attributes, expected: params[:expected_revision], confirmation: confirmation)
    render json: base_payload.merge(item: present(subject.reload))
  end

  private

  def render_team_activity_review(error)
    render json: base_payload.merge(error: error.code, review: error.review), status: error.status
  end

  def authority
    @authority ||= JrcContactCenter::AccessAuthorization.new(context: pundit_user)
  end

  def filter_status(relation)
    return filter_team_status(relation) unless users?
    return relation if params[:status].blank?

    eligible = JrcContactCenter::AccessGrant.where(account: Current.account, eligible: true).select(:account_user_id)
    return relation.where(id: eligible) if params[:status] == 'eligible'
    return relation.where.not(id: eligible) if params[:status] == 'pending'

    raise JrcContactCenter::OperationError, 'invalid_access_authorization'
  end

  def filter_team_status(relation)
    return relation if params[:status].blank?

    inactive = JrcContactCenter::TeamState.where(account: Current.account, active: false).select(:team_id)
    return relation.where.not(id: inactive) if params[:status] == 'active'
    return relation.where(id: inactive) if params[:status] == 'inactive'

    raise JrcContactCenter::OperationError, 'invalid_access_authorization'
  end

  def confirmation
    value = params[:manager_confirmation]
    value.respond_to?(:permit) ? value.permit(:confirmed, :review_token).to_h.symbolize_keys : nil
  end

  def users?
    params[:subject_type] == 'users'
  end

  def subjects
    return Current.account.account_users.includes(:user, :custom_role) if users?
    return Current.account.teams if params[:subject_type] == 'teams'

    raise ActiveRecord::RecordNotFound
  end

  def present(subject)
    grant = authority.grant_for(subject)
    payload = { id: subject.id, name: users? ? subject.user.name : subject.name,
                eligible: grant.eligible, allowed: grant.allowed, denied: grant.denied,
                revision: authority.revision(subject, grant) }
    unless users?
      return payload.merge(member_count: subject.team_members.count,
                           active: JrcContactCenter::TeamState.source_active?(account: Current.account, team_id: subject.id))
    end

    payload.merge(user_permissions_payload(subject))
  end

  def user_permissions_payload(subject)
    sources = JrcContactCenter::PermissionSources.new(account: Current.account, member: subject)
    details = {
      user_id: subject.user_id, profile: sources.profile, inherited: sources.inherited_permissions, effective: authority.effective(subject)
    }
    details[:origins] = sources.origins if action_name == 'show'
    details
  end

  def access_attributes
    values = params.require(:authorization)
    raise JrcContactCenter::OperationError, 'invalid_access_authorization' unless values.respond_to?(:permit)

    allowed_keys = users? ? %w[eligible allowed denied] : %w[allowed active]
    raise JrcContactCenter::OperationError, 'invalid_access_authorization' unless (values.keys - allowed_keys).empty?

    validate_access_types!(values)
    values.permit(:eligible, :active, allowed: [], denied: []).to_h
  end

  def validate_access_types!(values)
    invalid = %i[eligible active].any? { |key| values.key?(key) && [true, false].exclude?(values[key]) }
    raise JrcContactCenter::OperationError, 'invalid_access_authorization' if invalid

    %i[allowed denied].each { |key| validate_permission_array!(values, key) }
  end

  def validate_permission_array!(values, key)
    return unless values.key?(key)

    valid = values[key].is_a?(Array) && values[key].all?(String)
    raise JrcContactCenter::OperationError, 'invalid_access_authorization' unless valid
  end
end
