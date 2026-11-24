# frozen_string_literal: true

# Internal destination adapter, not a dispatcher. Its caller must retain the
# original-actor transaction, immutable trigger/readiness and atomic receipt.
# No native call hook, job or endpoint invokes this adapter during installation.
class JrcContactCenter::EndingActions::ProjectTaskDestination
  def initialize(account:, member:)
    @account = account
    @member = JrcOperations::Access.refresh(member)
  end

  def call(parameters:, trigger_at:, timezone:, correlation_id:)
    raise Pundit::NotAuthorizedError unless @member && @member.account_id == @account.id

    row = JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: @member).call(parameters)
    project = JrcOperations::Access.projects(@member).find(row.fetch('project_id'))
    attributes = attributes_for(row, trigger_at, timezone)
    JrcProjects::Tasks::Create.call(account_user: @member, project: project, attributes: attributes, correlation_id: correlation_id)
  end

  private

  def attributes_for(row, trigger_at, timezone)
    values = row.fetch('attributes').deep_dup
    offset = row.fetch('due_after_days')
    unless offset.nil?
      zone = Time.find_zone!(timezone)
      raise JrcContactCenter::OperationError, 'ending_action_timezone_unavailable' unless zone

      values['due_on'] = (trigger_at.in_time_zone(zone).to_date + offset).iso8601
    end
    actual = row.merge('attributes' => values, 'due_after_days' => nil)
    JrcContactCenter::EndingActions::TaskDefinition.new.call(actual).fetch('attributes')
  end
end
