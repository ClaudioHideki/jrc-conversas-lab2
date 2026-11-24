# frozen_string_literal: true

# Deliberately bounded audit classification. Raw exception messages may include
# SQL, client text or private project names and must never be copied to history.
class JrcContactCenter::EndingActions::AttemptFailure
  def self.call(error)
    case error
    when Pundit::NotAuthorizedError then ['blocked', 'authorization_denied']
    when ActiveRecord::RecordNotFound then ['blocked', 'reference_unavailable']
    when JrcContactCenter::OperationError then operation_failure(error)
    else ['failed', 'destination_failure']
    end
  end

  def self.operation_failure(error)
    code = case error.code
           when 'ending_action_pending_permanently_blocked' then 'deactivated'
           when 'ending_action_requires_agent_confirmation' then 'confirmation_required'
           when 'ending_action_trigger_pending' then 'trigger_pending'
           else 'operation_unavailable'
           end
    ['blocked', code]
  end
  private_class_method :operation_failure
end
