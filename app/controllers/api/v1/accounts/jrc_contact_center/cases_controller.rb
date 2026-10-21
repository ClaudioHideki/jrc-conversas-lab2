# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::CasesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    cases = scoped_cases.order(updated_at: :desc).limit(limit)
    cases = cases.where(status: params[:status]) if params[:status].present?
    render json: base_payload.merge(items: cases.map { |record| serialize(record) })
  end

  def show
    authorize_contact_center!
    record = scoped_cases.find(params[:id])
    events = record.events.order(:occurred_at).map do |event|
      event.as_json(only: %i[id actor_account_user_id event_type occurred_at data])
    end
    render json: base_payload.merge(item: serialize(record).merge('events' => events))
  end

  def create
    authorize_contact_center!(:operate?)
    attributes = case_params
    ensure_contact_center_assignment!(queue_id: attributes[:queue_id], owner_account_user_id: attributes[:owner_account_user_id],
                                      require_accessible_assignment: true)
    record = JrcContactCenter::Case.create!(attributes.merge(account: Current.account, protocol: next_protocol))
    record.events.create!(account: Current.account, actor_account_user: Current.account_user, event_type: 'created',
                          occurred_at: Time.current, data: { status: record.status })
    render json: base_payload.merge(item: serialize(record)), status: :created
  end

  def update
    authorize_contact_center!(:operate?)
    record = scoped_cases.find(params[:id])
    attributes = case_params
    authorize_case_assignment!(record, attributes)
    update_case(record, attributes)
    render json: base_payload.merge(item: serialize(record))
  end

  private

  def authorize_case_assignment!(record, attributes)
    effective_queue = attributes.key?(:queue_id) ? attributes[:queue_id] : record.queue_id
    effective_owner = attributes.key?(:owner_account_user_id) ? attributes[:owner_account_user_id] : record.owner_account_user_id
    ensure_contact_center_assignment!(queue_id: effective_queue, owner_account_user_id: effective_owner, require_accessible_assignment: true)
  end

  def update_case(record, attributes)
    previous = record.slice('status', 'owner_account_user_id', 'priority')
    record.update!(attributes)
    record.events.create!(account: Current.account, actor_account_user: Current.account_user, event_type: 'updated',
                          occurred_at: Time.current, data: { before: previous, after: record.slice(*previous.keys) })
  end

  def scoped_cases
    contact_center_access.cases
  end

  def limit
    params.fetch(:limit, 100).to_i.clamp(1, 200)
  end

  def case_params
    params.require(:case).permit(:contact_id, :company_id, :call_session_id, :owner_account_user_id, :unit_id, :queue_id,
                                 :channel, :category, :subcategory, :priority, :status, :due_at, :summary, :details, metadata: {})
  end

  def next_protocol
    loop do
      value = "CC-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(4).upcase}"
      return value unless JrcContactCenter::Case.where(account: Current.account).exists?(protocol: value)
    end
  end

  def serialize(record)
    record.as_json(only: %i[id protocol contact_id company_id call_session_id owner_account_user_id unit_id queue_id channel category
                            subcategory priority status due_at summary details metadata lock_version created_at updated_at])
  end
end
