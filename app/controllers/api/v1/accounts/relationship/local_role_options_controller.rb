class Api::V1::Accounts::Relationship::LocalRoleOptionsController < Api::V1::Accounts::Relationship::BaseController
  def index
    response.headers['Cache-Control'] = 'no-store'
    scope_key = params.fetch(:scope_key, 'account')
    context = relationship_context
    context.authorize_configuration_scope!(scope_key)
    signature = context.access_signature
    rows = context.assignable_users
    query = params[:q].to_s.strip.first(100)
    rows = rows.where('users.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(query)}%") if query.present?
    records, meta = page(rows.order(:name, :id))
    payload = records.map { |user| { id: user.id, name: user.name, active: user.active_for_authentication? } }
    fresh = JrcRelationship::Context.new(context.member)
    fresh.authorize_configuration_scope!(scope_key)
    raise Pundit::NotAuthorizedError unless fresh.access_signature == signature && fresh.user.reload.active_for_authentication?
    render json: { payload: payload, meta: meta }
  end
end
