# frozen_string_literal: true

# Response-local checks for GET serialization inside OperationsController's
# repeatable-read transaction. Never pass these decorated policies to commands.
# The original policies, scopes and their authorization rules remain unchanged.
class JrcServiceDesk::ReadProjection
  attr_reader :context

  def initialize(user_context)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    @policies = {}
  end

  def policy(record, policy_class: nil)
    @policies.fetch([record, policy_class]) do |key|
      policy = policy_class ? policy_class.new(context.to_h, record) : Pundit.policy!(context.to_h, record)
      if policy.is_a?(JrcServiceDesk::OperationalPolicy)
        policy.extend(Checks)
        policy.response_projection = self
      end
      @policies[key] = policy
    end
  end

  module Checks
    attr_writer :response_projection

    def show?
      return @show if defined?(@show)

      @show = super
    end

    def scoped_permission?(permission)
      @response_scoped_permissions ||= {}
      @response_scoped_permissions.fetch(permission) { @response_scoped_permissions[permission] = super }
    end

    protected

    def operational_context
      @response_projection.context
    end

    def capability?(name)
      @response_capabilities ||= {}
      @response_capabilities.fetch(name) { @response_capabilities[name] = super }
    end

    def record_unit_allowed?
      return @record_unit_allowed if defined?(@record_unit_allowed)

      @record_unit_allowed = super
    end

    def record_unit_visible?
      return @record_unit_visible if defined?(@record_unit_visible)

      @record_unit_visible = super
    end

    def parent_policy
      @response_projection.policy(record.ticket)
    end
  end
  private_constant :Checks
end
