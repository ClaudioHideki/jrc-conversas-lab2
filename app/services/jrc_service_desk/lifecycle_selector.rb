# frozen_string_literal: true

class JrcServiceDesk::LifecycleSelector
  def initialize(ticket)
    @ticket = ticket
  end

  def applicable
    return nil if @ticket.service && !@ticket.service.active?
    if @ticket.lifecycle_policy_version_id
      version = @ticket.lifecycle_policy_version
      return nil unless in_scope?(version) && version.lifecycle_policy.enabled?
      return version
    end
    scope = JrcServiceDesk::LifecyclePolicy.where(account_id: @ticket.account_id, unit_id: @ticket.unit_id)
    specific = @ticket.service_id && scope.find_by(service_id: @ticket.service_id)
    chosen = specific || scope.find_by(service_id: nil)
    return nil unless chosen&.enabled? && chosen.current_version
    version = chosen.current_version
    in_scope?(version) && version.lifecycle_policy_id == chosen.id ? version : nil
  end

  private

  def in_scope?(version)
    version && version.account_id == @ticket.account_id && version.unit_id == @ticket.unit_id &&
      (!version.lifecycle_policy.service_id || version.lifecycle_policy.service_id == @ticket.service_id)
  end
end
