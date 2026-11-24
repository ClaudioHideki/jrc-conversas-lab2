# frozen_string_literal: true

class JrcCulture::RosterController < JrcCulture::BaseController
  before_action :require_admin

  def index
    grants = JrcCulture::Grant.where(account: access.account, unit_id: access.admin_unit_ids, role: 'employee')
    grants = grants.where(unit_id: access.admin_scope_id!(params[:unit_id])) if params[:unit_id].present?
    page = params[:page].to_i.clamp(1, 10_000)
    records = grants.includes(:unit, account_user: :user).order(active: :desc, id: :desc).offset((page - 1) * 30).limit(30)
    render json: {
      page: page, pages: [(grants.count.to_f / 30).ceil, 1].max,
      collaborators: records.map do |grant|
        { id: grant.id, name: grant.account_user&.user&.name, member_id: grant.account_user_id,
          unit_id: grant.unit_id || JrcCulture::Access::ACCOUNT_SCOPE, unit: grant.unit&.name || JrcCulture::Access::ACCOUNT_SCOPE_LABEL,
          department: grant.department, active: grant.active? && grant.account_user.present? }
      end
    }
  end

  def directory
    unit_id = access.admin_scope_id!(params[:unit_id])
    query = "%#{ApplicationRecord.sanitize_sql_like(params[:culture_person_query].to_s.strip.first(100))}%"
    rows = access.employee_directory(unit_id).where('users.name ILIKE :query OR users.email ILIKE :query', query: query).limit(50)
    render json: {
      users: rows.filter_map do |member|
        next unless member.user.active_for_authentication?

        { id: member.id, name: member.user.name, email: member.user.email }
      end
    }
  end

  def create
    grant = access.account.with_lock('FOR NO KEY UPDATE') do
      unit_id = access.admin_scope_id!(params.require(:unit_id))
      JrcCulture::Roster.new(access).enable!(unit_id: unit_id, member_id: params.require(:member_id), department: params[:department])
    end
    render json: { id: grant.id }, status: :created
  end

  def destroy
    access.account.with_lock('FOR NO KEY UPDATE') { JrcCulture::Roster.new(access).disable!(params[:id]) }
    head :no_content
  end

  private

  def require_admin
    access.admin!
  end
end
