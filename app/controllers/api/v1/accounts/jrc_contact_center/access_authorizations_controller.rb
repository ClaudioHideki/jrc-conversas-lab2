class Api::V1::Accounts::JrcContactCenter::AccessAuthorizationsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action -> { authority.authorize! }
  before_action -> { response.headers['Cache-Control'] = 'no-store' }

  def index
    params[:page] = 1 if params[:page].blank?
    relation = subjects
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
    authority.update!(subject: subject, attributes: access_attributes, expected: params[:expected_revision])
    render json: base_payload.merge(item: present(subject.reload))
  end

  private

  def authority
    @authority ||= JrcContactCenter::AccessAuthorization.new(context: pundit_user)
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
    return payload.merge(member_count: subject.team_members.count) unless users?

    sources = JrcContactCenter::PermissionSources.new(account: Current.account, member: subject)
    payload.merge(user_id: subject.user_id, profile: sources.profile, inherited: sources.inherited, effective: authority.effective(subject))
  end

  def access_attributes
    values = params.require(:authorization)
    allowed_keys = users? ? %w[eligible allowed denied] : ['allowed']
    raise JrcContactCenter::OperationError, 'invalid_access_authorization' unless (values.keys - allowed_keys).empty?

    validate_access_types!(values)
    values.permit(:eligible, allowed: [], denied: []).to_h
  end

  def validate_access_types!(values)
    if values.key?(:eligible) && ![true, false].include?(values[:eligible])
      raise JrcContactCenter::OperationError, 'invalid_access_authorization'
    end
    %i[allowed denied].each do |key|
      next unless values.key?(key)

      valid = values[key].is_a?(Array) && values[key].all? { |value| value.is_a?(String) }
      raise JrcContactCenter::OperationError, 'invalid_access_authorization' unless valid
    end
  end
end
