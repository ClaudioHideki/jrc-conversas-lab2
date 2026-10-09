# frozen_string_literal: true

class JrcServiceDesk::ServicePortalConfiguration
  CAPABILITIES = %i[tickets_create conversations_link customers_view lookups_view].freeze

  def initialize(service)
    @service = service
    @member = service.portal_execution_membership&.account_user
  end

  def ready?
    active_catalogue? && @service.portal_inbox&.channel_type == 'Channel::WebWidget' &&
      @service.portal_execution_membership&.active? && @member
  end

  def active_catalogue?
    @service.active? && @service.default_priority&.active?
  end

  def permitted?
    context = JrcServiceDesk::OperationalContext.new(account: @service.account, user: @member.user, account_user: @member)
    return false unless context.unit_allowed?(@service.unit) && CAPABILITIES.all? { |key| context.capability?(key) }

    JrcServiceDesk::NativeExecutionContext.with(context.to_h) { InboxPolicy.new(context.to_h, @service.portal_inbox).show? }
  end
end
