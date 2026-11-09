# frozen_string_literal: true

class JrcServiceDesk::PortalEstablishments
  def initialize(identity:, proof:)
    @identity = identity
    @proof = proof
  end

  def scope
    raise Pundit::NotAuthorizedError unless @identity.inbox.account.feature_enabled?('jrc_customer_master')

    @proof.verify!(identity: @identity)
    ids = @proof.establishment_ids(identity: @identity)
    JrcCustomers::EstablishmentMetadata.scope(@identity.inbox.account).where(id: ids)
  end

  def find!(id, service:)
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::PortalRoutingConfiguration.read(service.unit)['stores_enabled'] == true

    scope.lock('FOR SHARE').find(JrcServiceDesk::Input.id(id))
  end
end
