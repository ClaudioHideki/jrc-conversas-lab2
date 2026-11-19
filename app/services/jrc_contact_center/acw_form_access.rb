# frozen_string_literal: true

# This account-wide library follows the existing global ACW configuration authority.
# Attendance users must never receive this manager catalog.
class JrcContactCenter::AcwFormAccess
  attr_reader :context, :access

  def initialize(context:)
    @context = context.slice(:account, :account_user, :user).transform_values(&:reload)
    @access = JrcContactCenter::AccessScope.new(user_context: @context)
    valid = @context.fetch(:user).active_for_authentication? && access.policy.configure?
    raise Pundit::NotAuthorizedError unless valid

    coverage = JrcCrm::CorporateCoverage.new(account: @context.fetch(:account), user: @context.fetch(:user))
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end

  def relation
    JrcContactCenter::AcwFormTemplate.where(account: context.fetch(:account))
  end

  def find!(id)
    relation.find(id)
  end
end
