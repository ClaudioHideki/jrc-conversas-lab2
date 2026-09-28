# frozen_string_literal: true

# Account-level STRUCTURAL administration, explicitly delegated in native CustomRole.
# It does not implement unit_scope and is never accepted by operational services.
class JrcServiceDesk::StructureContext
  attr_reader :native

  def initialize(user_context)
    @native = JrcServiceDesk::OperationalContext.new(user_context)
  end

  delegate :account, :user, :account_user, :to_h, to: :native

  def available?
    native.available? && account_user.role == 'administrator' &&
      JrcServiceDesk::InitializerAuthority.client_user?(user) && native.capability?(:structure_view) && initialized?
  end

  def allowed?(resource = nil)
    available? && (resource.nil? || native.capability?(JrcServiceDesk::StructureContract::CAPABILITIES.fetch(resource.to_s)))
  end

  def initialized?
    return false unless native.available?
    # Existing explicitly provisioned accounts remain usable; inactive grants are history,
    # not renewed access. A new empty Account can ONLY use the human staff initializer.
    JrcServiceDesk::UnitMembership.where(account_id: account.id).exists? ||
      Audited::Audit.where(request_uuid: JrcServiceDesk::InitializeAccountService.marker(account.id)).exists?
  end
end
