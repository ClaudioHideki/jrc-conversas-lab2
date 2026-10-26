# frozen_string_literal: true

# Explicit provisioning of grants to existing users, using native account admin
# authority. Nothing creates, invites, activates or backfills a person implicitly.
class Api::V1::Accounts::JrcServiceDesk::RequesterPortalController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :require_portal_administrator
  rescue_from ArgumentError, KeyError, ActiveRecord::RecordInvalid, with: :invalid_input

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
    fields = %w[user_id contact_inbox_id active role visible_contact_ids expose_sla expires_at]
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, fields)
    identity = ContactInbox.joins(:inbox).where(inboxes: { account_id: Current.account.id })
                           .find(::JrcServiceDesk::Input.id(values.fetch('contact_inbox_id')))
    grant = ::JrcServiceDesk::PortalGrant.new(values.except('contact_inbox_id').merge(
      account: Current.account, contact_inbox: identity, contact: identity.contact, inbox: identity.inbox,
      company_id: identity.contact.company_id, granted_by: current_user
    ))
    ::JrcServiceDesk::PortalGrant.transaction do
      grant.save!
      audit(grant, 'create', grant.attributes.slice('active', 'role', 'expose_sla', 'visible_contact_ids', 'expires_at'))
    end
    render json: { grant: grant_payload(grant) }, status: :created
  end

  def change_grant
    values = ::JrcServiceDesk::Input.attributes(request.request_parameters, %w[active role visible_contact_ids expose_sla expires_at])
    grant = ::JrcServiceDesk::PortalGrant.where(account: Current.account).find(::JrcServiceDesk::Input.id(params[:id]))
    grant.with_lock do
      grant.update!(values)
      audit(grant, 'update', values)
    end
    render json: { grant: grant_payload(grant) }
  end

  private

  def require_portal_administrator
    head :forbidden unless Current.account_user.administrator? && Current.account.feature_enabled?('jrc_service_desk')
  end

  def grant_payload(grant)
    grant.attributes.slice('id', 'user_id', 'company_id', 'contact_id', 'contact_inbox_id', 'active', 'role', 'visible_contact_ids', 'expose_sla', 'expires_at')
  end

  def audit(record, action, changes)
    Audited::Audit.create!(auditable: record, associated: Current.account, user: current_user, action: action,
                          audited_changes: changes, request_uuid: request.request_id, comment: 'requester_portal_access')
  end

  def invalid_input
    render json: { code: 'invalid_input' }, status: :unprocessable_entity
  end
end
