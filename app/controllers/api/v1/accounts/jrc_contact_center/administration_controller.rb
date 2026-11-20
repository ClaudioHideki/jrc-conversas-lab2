class Api::V1::Accounts::JrcContactCenter::AdministrationController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    render json: base_payload.merge(administration.call)
  end

  def show
    authorize_contact_center!
    administration.authorize_section!(params[:id])
    case params[:id]
    when 'extensions' then render_extensions
    when 'pabx' then render_pabx
    when 'audit', 'events' then render_events
    when 'teams' then render_teams
    when 'integrations' then render_integrations
    else
      render json: base_payload.merge(items: [], state: 'pending_contract')
    end
  end

  private

  def render_integrations
    entries = JrcContactCenter::Providers::JrcPabxAdapter.new(account: Current.account).capabilities
    entries = entries.select { |name, _status| name.include?(params[:q].to_s) } if params[:q].present?
    render json: base_payload.merge(items: entries.map { |name, status| { name: name, status: status } })
  end

  def render_teams
    authorize ::Team, :index?
    organizational = JrcContactCenter::OrganizationalScope.new(account: Current.account, account_user: Current.account_user)
    relation = Current.account.teams.order(:name, :id)
    relation = relation.where(id: TeamMember.where(user: Current.user).select(:team_id)) if organizational.restricted?
    payload = team_list_payload(filter_team_activity(relation))
    payload[:can_manage] = team_management_allowed?(organizational)
    payload[:agents] = team_agent_options if payload[:can_manage]
    render json: payload
  end

  def team_list_payload(relation)
    inactive = JrcContactCenter::TeamState.where(account: Current.account, team_id: relation.select(:id), active: false).pluck(:team_id)
    list_payload(search_records(relation, fields: ['name'])) do |team|
      team.as_json(only: %i[id name description updated_at]).merge('cc_active' => !inactive.include?(team.id))
    end
  end

  def filter_team_activity(relation)
    return relation if params[:status].blank?

    inactive = JrcContactCenter::TeamState.where(account: Current.account, active: false).select(:team_id)
    return relation.where.not(id: inactive) if params[:status] == 'active'
    return relation.where(id: inactive) if params[:status] == 'inactive'

    raise JrcContactCenter::OperationError, 'invalid_access_authorization'
  end

  def team_management_allowed?(organizational)
    !organizational.restricted? && TeamPolicy.new(pundit_user, ::Team).create?
  end

  def team_agent_options
    Current.account.account_users.includes(:user).order(:id).map { |member| { user_id: member.user_id, name: member.user.available_name } }
  end

  def administration
    @administration ||= JrcContactCenter::Administration.new(context: pundit_user, access: contact_center_access)
  end

  def render_extensions
    relation = Current.account.sip_credentials.includes(:user).order(:extension, :id)
    organizational = JrcContactCenter::OrganizationalScope.new(account: Current.account, account_user: Current.account_user)
    relation = relation.where(user: Current.user) if organizational.restricted?
    relation = search_extensions(relation) if params[:q].present?
    payload = list_payload(relation) do |credential|
      { id: credential.id, name: credential.user.available_name, extension: credential.extension,
        enabled: credential.enabled?, configured: credential.configured? }
    end
    render json: payload
  end

  def search_extensions(relation)
    query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.first(100))}%"
    relation.joins(:user).where('sip_credentials.extension ILIKE :query OR users.name ILIKE :query', query: query)
  end

  def render_pabx
    row = Current.account.telephony_integration
    # Infrastructure secrets and transport addresses are not a module-admin grant.
    item = { configured: row.present? && Pabx::Settings.new(row).configured?, state: 'pending_external_homologation',
             last_sync_at: row&.pabx_sync_state&.fetch('last_success_at', nil) }
    render json: base_payload.merge(items: [item])
  end

  def render_events
    records = contact_center_access.events.order(received_at: :desc, id: :desc)
    records = search_records(records, fields: ['event_type'])
    records = records.where(event_type: params[:event_type]) if params[:event_type].present?
    payload = list_payload(records) do |record|
      record.as_json(only: %i[id event_type status received_at occurred_at attempts signature_verified])
    end
    render json: payload
  end
end
