# frozen_string_literal: true

class JrcServiceDesk::StructurePolicy
  def initialize(user_context, record)
    @context = JrcServiceDesk::StructureContext.new(user_context)
    @record = record
  end

  def context?
    @record.is_a?(::Account) && @context.available? && @record.id == @context.account.id
  end

  def index?
    @context.available? && resource.present?
  end

  def show?
    index? && @record.respond_to?(:account_id) && @record.account_id == @context.account.id
  end

  def create?
    show? && @context.allowed?(resource)
  end

  alias update? create?
  alias receipt? create?

  def members?
    context? && @context.allowed?('unit_memberships')
  end

  def destroy?
    false
  end

  private

  def resource
    JrcServiceDesk::StructureContract::RESOURCES.find do |name|
      klass = JrcServiceDesk::StructureRecords.model(name)
      @record == klass || @record.is_a?(klass)
    end
  end

  class Scope
    def initialize(user_context, scope)
      @context = JrcServiceDesk::StructureContext.new(user_context)
      @scope = scope
    end

    def resolve
      allowed = JrcServiceDesk::StructureContract::RESOURCES.any? { |r| @scope == JrcServiceDesk::StructureRecords.model(r) }
      return @scope.none unless allowed && @context.available?
      @scope.where(account_id: @context.account.id)
    end
  end
end
