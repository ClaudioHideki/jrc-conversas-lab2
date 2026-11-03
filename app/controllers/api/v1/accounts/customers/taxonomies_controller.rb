class Api::V1::Accounts::Customers::TaxonomiesController < Api::V1::Accounts::Customers::BaseController
  before_action :authorize_admin!, except: %i[index show members overrides history preview]
  before_action :set_taxonomy, except: %i[index create preview]
  before_action :private_response

  def index
    scope = JrcCustomers::Taxonomy.where(account_id: Current.account.id)
    scope = scope.where(kind: params[:kind]) if params[:kind].present?
    records, meta = page_scope(scope.ordered)
    render json: { payload: records.map { |record| serialize(record) }, meta: meta,
                   fields: JrcCustomers::SegmentCriteria::FIELDS, modules: JrcCustomers::Taxonomy::MODULES }
  end

  def show
    render json: { payload: serialize(@taxonomy) }
  end

  def create
    record = nil
    Current.account.with_lock do
      choices = JrcCustomers::SegmentMembers.resolve_choices(account: Current.account, actor: Current.user, choices: manual_choices)
      record = writer.save!(taxonomy: JrcCustomers::Taxonomy.new(account: Current.account), attributes: taxonomy_params)
      choices.each do |choice|
        writer.override!(taxonomy: record, kind: choice['subject_kind'], id: choice['subject_id'], mode: choice['mode'])
      end
    end
    render json: { payload: serialize(record) }, status: :created
  end

  def update
    record = writer.save!(taxonomy: @taxonomy, attributes: taxonomy_params, expected_revision: params.dig(:taxonomy, :revision))
    render json: { payload: serialize(record) }
  end

  def destroy
    raise ActionController::BadRequest, 'Explicit confirmation required' unless params[:confirm] == true

    writer.destroy!(taxonomy: @taxonomy)
    head :no_content
  end

  def preview
    # Preview reuses stored manual choices while editing, without changing the definition.
    @taxonomy = if params[:taxonomy_id].present?
                  JrcCustomers::Taxonomy.where(account_id: Current.account.id).find(params[:taxonomy_id])
                else
                  JrcCustomers::Taxonomy.new(account: Current.account)
                end
    @taxonomy.assign_attributes(taxonomy_params)
    render_members
  end

  def members
    render_members
  end

  def overrides
    records, meta = page_scope(member_query.overrides.order(:id))
    render json: { payload: records.map { |record| override_json(record) }, meta: meta }
  end

  def set_override
    choice = writer.override!(taxonomy: @taxonomy, kind: params[:subject_kind], id: params[:subject_id], mode: params[:mode])
    render json: { payload: override_json(choice) }
  end

  def remove_override
    writer.remove_override!(taxonomy: @taxonomy, id: params[:override_id])
    head :no_content
  end

  def history
    scope = JrcCrm::AuditEvent.where(account_id: Current.account.id, resource_type: 'JrcCustomers::Taxonomy', resource_id: @taxonomy.id)
    records, meta = page_scope(scope.order(created_at: :desc, id: :desc))
    actors = Current.account.users.where(id: records.select { |event| event.actor_type == 'User' }.map(&:actor_id)).pluck(:id, :name).to_h
    payload = records.map do |event|
      { id: event.id, kind: event.event_type, at: event.created_at, actor_name: event.actor_type == 'User' ? actors[event.actor_id] : nil }
    end
    render json: { payload: payload, meta: meta }
  end

  private

  def set_taxonomy
    @taxonomy = JrcCustomers::Taxonomy.where(account_id: Current.account.id).find(params[:id])
  end

  def taxonomy_params
    params.require(:taxonomy).permit(:kind, :name, :active, :position, :description, :selection_mode,
                                     modules: [], criteria: [:match, { rules: %i[field operator value] }])
  end

  def serialize(record)
    record.as_json(only: %i[id kind name active position description selection_mode criteria modules created_at updated_at])
          .merge('revision' => record.updated_at&.iso8601(6))
  end

  def writer
    JrcCustomers::TaxonomyWriter.new(account: Current.account, actor: Current.user)
  end

  def member_query
    @member_query ||= JrcCustomers::SegmentMembers.new(account: Current.account, actor: Current.user, taxonomy: @taxonomy,
                                                       manual_choices: action_name == 'preview' ? manual_choices : [])
  end

  def manual_choices
    params.permit(taxonomy: { manual_choices: %i[subject_kind subject_id mode] }).dig(:taxonomy, :manual_choices)&.map(&:to_h) || []
  end

  def render_members
    kind = params.fetch(:subject_kind, 'companies')
    raise ActionController::BadRequest, 'Invalid subject kind' unless %w[companies contacts].include?(kind)

    records, meta = page_scope(matching_members(kind).order(:name, :id))
    payload = serializer.public_send(kind, records.to_a)
    render json: { payload: payload, meta: meta, counts: { companies: member_query.companies.count, contacts: member_query.contacts.count } }
  end

  def matching_members(kind)
    scope = member_query.public_send(kind)
    return JrcCustomers::ContactQuery.new(account: Current.account, scope: scope, query: params[:q]).call if kind == 'contacts'

    filtered = JrcCustomers::DirectoryQuery.new(account: Current.account, filters: { q: params[:q] }).call
    scope.where(id: filtered.reselect(:id))
  end

  def override_json(record)
    subject = record.company || record.contact
    { id: record.id, subject_kind: record.company_id ? 'companies' : 'contacts', subject_id: subject.id, name: subject.name, mode: record.mode }
  end

  def private_response
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
end
