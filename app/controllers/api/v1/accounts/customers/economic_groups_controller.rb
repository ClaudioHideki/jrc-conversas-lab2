class Api::V1::Accounts::Customers::EconomicGroupsController < Api::V1::Accounts::Customers::BaseController
  before_action :set_group, except: %i[index create]
  before_action :private_response

  def index
    scope = directory.scope
    if params[:q].present?
      term = ActiveRecord::Base.sanitize_sql_like(params.permit(:q)[:q].to_s.strip.first(200))
      scope = scope.where('name ILIKE ?', "%#{term}%")
    end
    records, meta = page_scope(scope.ordered)
    render json: { payload: records.map { |group| serialize(group) }, meta: meta }
  end

  def show
    render json: { payload: serialize(@group) }
  end

  def create
    group = writer.save!(group: JrcCustomers::EconomicGroup.new(account: Current.account), attributes: group_params)
    render json: { payload: serialize(group) }, status: :created
  end

  def update
    group = writer.save!(group: @group, attributes: group_params, expected_revision: revision!)
    render json: { payload: serialize(group) }
  end

  def destroy
    raise ActionController::BadRequest, 'Explicit confirmation required' unless params[:confirm] == true

    writer.destroy!(group: @group, expected_revision: revision!)
    head :no_content
  end

  def members
    scope = directory.members(@group)
    filtered = JrcCustomers::DirectoryQuery.new(account: Current.account, filters: params.permit(:q)).call
    records, meta = page_scope(scope.where(id: filtered.reselect(:id)).order(:name, :id))
    render json: { payload: serializer.companies(records.to_a), meta: meta }
  end

  def assign
    raise ActionController::BadRequest, 'company_revision is required; reload the company' if params[:company_revision].blank?

    company = writer.assign!(group: @group, company_id: params[:company_id], revision: params[:company_revision],
                             remove: params[:remove] == true, confirm_transfer: params[:confirm_transfer] == true)
    render json: { payload: serializer.company(company), group: serialize(@group.reload) }
  end

  def history
    scope = JrcCrm::AuditEvent.where(account_id: Current.account.id, resource_type: 'JrcCustomers::EconomicGroup', resource_id: @group.id)
    records, meta = page_scope(scope.order(created_at: :desc, id: :desc))
    actors = Current.account.users.where(id: records.select { |event| event.actor_type == 'User' }.map(&:actor_id)).pluck(:id, :name).to_h
    payload = records.map do |event|
      { id: event.id, kind: event.event_type, at: event.created_at, actor_name: event.actor_type == 'User' ? actors[event.actor_id] : nil }
    end
    render json: { payload: payload, meta: meta }
  end

  private

  def directory
    @directory ||= JrcCustomers::EconomicGroupDirectory.new(account: Current.account, actor: Current.user)
  end

  def writer
    JrcCustomers::EconomicGroupWriter.new(account: Current.account, actor: Current.user)
  end

  def set_group
    @group = directory.scope.find(params[:id])
  end

  def group_params
    params.require(:economic_group).permit(:name, :description, :principal_company_id)
  end

  def revision!
    value = params[:revision] || params.dig(:economic_group, :revision)
    raise ActionController::BadRequest, 'revision is required; reload the economic group' if value.blank?

    value
  end

  def serialize(group)
    principal = directory.members(group).find_by(id: group.principal_company_id) if group.principal_company_id
    group.as_json(only: %i[id name description created_at updated_at]).merge(
      'revision' => group.updated_at&.iso8601(6), 'member_count' => directory.members(group).count,
      'principal_company' => principal&.attributes&.slice('id', 'name'),
      'can_manage' => Current.account_user.administrator? && directory.complete_coverage?(group)
    )
  end

  def private_response
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
end
