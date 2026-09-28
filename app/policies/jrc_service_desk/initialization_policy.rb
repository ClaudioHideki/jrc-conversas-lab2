# frozen_string_literal: true

# Structural control-plane exception, never a TicketPolicy or AccountUser impersonation.
class JrcServiceDesk::InitializationPolicy
  def initialize(context, record)
    @actor = context[:initializer]
    @account = context[:account]
    @record = record
  end

  def show?
    return false unless @record.is_a?(::Account) && @record.persisted? && @account.is_a?(::Account) && @record.id == @account.id
    account = ::Account.find_by(id: @account.id)
    account && account.active? && account.feature_enabled?('jrc_service_desk') == true &&
      JrcServiceDesk::InitializerAuthority.authorized?(@actor)
  end

  alias create? show?
  alias receipt? show?
end
