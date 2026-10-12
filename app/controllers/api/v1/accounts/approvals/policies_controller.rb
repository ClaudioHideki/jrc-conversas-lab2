class Api::V1::Accounts::Approvals::PoliciesController < Api::V1::Accounts::Approvals::BaseController
  def index
    relation = filtered(JrcApprovals::Policy.where(account_id: Current.account.id),
                        %w[state enabled issuer_company_id business_unit_id module_key event_key])
    rows = relation.includes(:current_version, author: :user).order(:id).filter_map do |record|
      authorization.authorize!('policy_manage', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
      payload(record)
    rescue Pundit::NotAuthorizedError
      nil
    end
    render json: paginated(rows)
  end

  def show
    render json: payload(readable_policy)
  end

  def versions
    record = readable_policy
    render json: paginated(record.versions.order(:version).map do |version|
      version.attributes.slice('id', 'version', 'digest', 'definition', 'publication', 'created_at').merge(
        'publisher_name' => version.publisher.user.name
      )
    end)
  end

  def create
    values = params.require(:policy).permit(:code, :name, :module_key, :event_key, :issuer_company_id, :business_unit_id,
                                            definition: {}).to_h.symbolize_keys
    render json: payload(service(JrcApprovals::Policies).create!(**values)), status: :created
  end

  def update
    values = params.require(:policy).permit(:name, definition: {}).to_h.symbolize_keys
    record = service(JrcApprovals::Policies).edit!(policy_id: params[:id], expected_version: params[:expected_version], **values)
    render json: payload(record)
  end

  %w[validate publish retire].each do |operation|
    define_method(operation) do
      record = service(JrcApprovals::Policies).public_send("#{operation}!", policy_id: params[:id], expected_version: params[:expected_version])
      result = payload(record)
      if operation == 'validate'
        plan = JrcApprovals::Eligibility.new(
          account: Current.account, company_id: record.issuer_company_id,
          unit_id: record.business_unit_id, catalog_key: "#{record.module_key}.#{record.event_key}"
        ).plan!(record.draft_definition)
        result['validation_plan'] = plan.map { |step| step.slice('code', 'quorum').merge('eligible_count' => step['principal_ids'].size) }
      end
      render json: result
    end
  end

  private

  def readable_policy
    record = JrcApprovals::Policy.where(account_id: Current.account.id).find(params[:id])
    authorization.authorize!('policy_manage', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    record
  end

  def payload(record)
    record.attributes.slice('id', 'code', 'name', 'state', 'enabled', 'lock_version', 'issuer_company_id', 'business_unit_id',
                            'module_key', 'event_key', 'current_version_id', 'draft_definition').merge(
                              'current_version' => record.current_version&.version,
                              'published_definition' => record.current_version&.definition, 'author_name' => record.author.user.name
                            )
  end
end
