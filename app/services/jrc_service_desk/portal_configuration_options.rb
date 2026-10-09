# frozen_string_literal: true

# Read-only choices from real native inboxes and active scoped memberships.
# Selecting a choice does not grant access or enable the catalogue.
class JrcServiceDesk::PortalConfigurationOptions
  CAPABILITIES = %i[tickets_create conversations_link customers_view lookups_view].freeze

  def initialize(user_context:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
  end

  def call(unit_id:, inbox_id: nil)
    unit = authorized_unit(unit_id)
    inboxes = inboxes()
    inbox = inbox_id && inboxes.find(JrcServiceDesk::Input.id(inbox_id))
    { contract_version: 1, account_id: @context.account.id.to_s, unit_id: unit.id.to_s,
      inboxes: inboxes.map { |row| { id: row.id.to_s, name: row.name, source: 'native_widget' } },
      execution_memberships: members(unit, inbox).map { |row| { id: row.id.to_s, name: row.account_user.user.name } } }
  end

  private

  def authorized_unit(unit_id)
    unit = @context.unit_scope.find(JrcServiceDesk::Input.id(unit_id))
    Pundit.authorize(@context.to_h, JrcServiceDesk::Service.new(account: @context.account, unit: unit), :update?)
    unit
  end

  def inboxes
    JrcServiceDesk::NativeExecutionContext.with(@context.to_h) do
      Pundit.policy_scope!(@context.to_h, @context.account.inboxes)
            .where(account_id: @context.account.id, channel_type: 'Channel::WebWidget').order(:name, :id)
    end
  end

  def members(unit, inbox)
    JrcServiceDesk::UnitMembership.where(account_id: @context.account.id, unit_id: unit.id, active: true)
                                  .includes(account_user: :user).order(:id).select { |row| eligible?(row, unit, inbox) }
  end

  def eligible?(membership, unit, inbox)
    member = membership.account_user
    actor = JrcServiceDesk::OperationalContext.new(account: @context.account, user: member.user, account_user: member)
    allowed = actor.unit_allowed?(unit) && CAPABILITIES.all? { |key| actor.capability?(key) }
    allowed &&= JrcServiceDesk::NativeExecutionContext.with(actor.to_h) { InboxPolicy.new(actor.to_h, inbox).show? } if inbox
    allowed
  end
end
