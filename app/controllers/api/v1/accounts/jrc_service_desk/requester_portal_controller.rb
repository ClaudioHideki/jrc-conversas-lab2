# frozen_string_literal: true

# Explicit provisioning of grants to existing users, using native account admin
# authority. Nothing creates, invites, activates or backfills a person implicitly.
class Api::V1::Accounts::JrcServiceDesk::RequesterPortalController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :require_portal_administrator
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, with: :invalid_input
  rescue_from ::JrcServiceDesk::IdempotencyConflict, with: :configuration_conflict

  def show
    render json: { enabled: Current.account.internal_attributes['requester_portal_enabled'] == true,
                   grants: ::JrcServiceDesk::PortalGrant.where(account: Current.account).order(:id).map { |grant| grant_payload(grant) } }
  end

  def update
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[enabled])
    enabled = values.fetch('enabled')
    raise ArgumentError unless [true, false].include?(enabled)

    Current.account.with_lock do
      Current.account.update!(internal_attributes: Current.account.internal_attributes.merge('requester_portal_enabled' => enabled))
      audit(Current.account, 'update', 'requester_portal_enabled' => enabled)
    end
    render json: { enabled: enabled }
  end

  def create
    fields = %w[user_id contact_inbox_id active role visible_contact_ids expose_sla expires_at establishment_ids]
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, fields)
    identity = ContactInbox.joins(:inbox).where(inboxes: { account_id: Current.account.id })
                           .find(::JrcServiceDesk::Input.id(values.fetch('contact_inbox_id')))
    grant = ::JrcServiceDesk::PortalGrant.new(values.except('contact_inbox_id').merge(
      account: Current.account, contact_inbox: identity, contact: identity.contact, inbox: identity.inbox,
      company_id: identity.contact.company_id, granted_by: current_user
    ))
    ::JrcServiceDesk::PortalGrant.transaction do
      grant.save!
      audit(grant, 'create', grant.attributes.slice('active', 'role', 'expose_sla', 'visible_contact_ids', 'expires_at', 'establishment_ids'))
    end
    render json: { grant: grant_payload(grant) }, status: :created
  end

  def change_grant
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[active role visible_contact_ids expose_sla expires_at establishment_ids expected_revision])
    grant = ::JrcServiceDesk::PortalGrant.where(account: Current.account).find(::JrcServiceDesk::Input.id(params[:id]))
    expected = values.delete('expected_revision')
    grant.with_lock do
      if values.key?('establishment_ids') && expected != grant.updated_at.iso8601(6)
        raise ::JrcServiceDesk::IdempotencyConflict
      end
      grant.update!(values)
      audit(grant, 'update', values)
    end
    render json: { grant: grant_payload(grant) }
  end

  def routing
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    units = context.view_unit_scope.order(:name, :id)
    render json: { units: units.map do |unit|
      { id: unit.id.to_s, name: unit.name, configuration: ::JrcServiceDesk::PortalRoutingConfiguration.read(unit),
        revision: ::JrcServiceDesk::PortalRoutingConfiguration.revision(unit),
        queues: ::JrcServiceDesk::Queue.where(account_id: Current.account.id, unit_id: unit.id, active: true).order(:name, :id)
          .map { |queue| { id: queue.id, name: queue.name } },
        assignees: unit.unit_memberships.operational.where(active: true, manual_assignment_enabled: true).includes(account_user: :user)
          .map { |member| { id: member.account_user_id, name: member.account_user.user.name } } }
    end }
  end

  def update_routing
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[unit_id revision configuration])
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    unit = context.view_unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    ::JrcServiceDesk::PortalRoutingConfiguration.save!(unit: unit, actor: Current.account_user,
      values: values.fetch('configuration'), expected_revision: values.fetch('revision'))
    routing
  rescue ::JrcServiceDesk::IdempotencyConflict
    render json: { code: 'configuration_changed' }, status: :conflict
  end

  def establishments
    scope = ::JrcCustomers::EstablishmentMetadata.scope(Current.account).order(:name, :id)
    render json: { establishments: scope.limit(1000).map { |company| ::JrcCustomers::EstablishmentMetadata.snapshot(company) } }
  end

  private

  def require_portal_administrator
    head :forbidden unless ::JrcOperations::Access.admin?(Current.account_user) && Current.account.feature_enabled?('jrc_service_desk')
  end

  def grant_payload(grant)
    { 'contact_name' => grant.contact.name, 'user_name' => grant.user.name, 'revision' => grant.updated_at.iso8601(6) }.merge(grant.attributes.slice('id', 'user_id', 'company_id', 'contact_id', 'contact_inbox_id', 'active', 'role', 'visible_contact_ids', 'expose_sla', 'expires_at', 'establishment_ids'))
  end

  def audit(record, action, changes)
    Audited::Audit.create!(auditable: record, associated: Current.account, user: current_user, action: action,
                          audited_changes: changes, request_uuid: request.request_id, comment: 'requester_portal_access')
  end

  def configuration_conflict
    render json: { code: 'configuration_changed' }, status: :conflict
  end

  def invalid_input
    render json: { code: 'invalid_input' }, status: :unprocessable_entity
  end
end
