# The first fenced native operation is a local database task edit. Do not add
# remote operations here: their preflight must run outside the effect transaction.
class JrcNico::NativeBrowserCommand
  class Rejected < StandardError; end
  VERSION = 'nico-native-v1'.freeze
  KEY = 'native_browser_command'.freeze

  def self.claim!(command, access)
    return unless command.tool == 'update_project_task'

    contract = descriptor(command, access).merge('expires_at' => 2.minutes.from_now.iso8601(6))
    command.execution_context = command.execution_context.merge(KEY => contract)
    # Old tabs do not recognize this discriminator and cannot send an unbound PATCH.
    command.result = command.result.merge('browser_action' => 'module_action_fenced',
                                          'native_execution' => { 'command_id' => command.id, 'contract' => VERSION })
  end

  def self.descriptor(command, access)
    raise Rejected unless command.tool == 'update_project_task'

    args = command.arguments
    task = args.except('project_id', 'task_id', 'clear_assignee', 'clear_parent')
    task['assignee_id'] = nil if args['clear_assignee']
    task['parent_id'] = nil if args['clear_parent']
    project_id = Integer(args.fetch('project_id'))
    task_id = Integer(args.fetch('task_id'))
    {
      'version' => VERSION, 'account_id' => access.account.id, 'user_id' => access.user.id,
      'tool' => command.tool, 'arguments_digest' => JrcServiceDesk::CanonicalJson.digest(args),
      'method' => 'PATCH',
      'path' => "/api/v1/accounts/#{access.account.id}/projects/projects/#{project_id}/tasks/#{task_id}",
      'body_digest' => JrcServiceDesk::CanonicalJson.digest('task' => task)
    }
  end

  def self.execute(account:, user:, request:)
    raise Rejected unless account && user

    command_id = request.headers['X-JRC-Nico-Command-Id'].to_s
    raise Rejected unless request.headers['X-JRC-Nico-Contract'] == VERSION && command_id.match?(/\A[1-9][0-9]{0,18}\z/)

    # Migration Execute/Reconciliation use this same account lock. Acceptance
    # cannot be revoked between the fresh checks and this local database effect.
    # NO KEY UPDATE conflicts with migration's account lock, but permits the
    # native audit FK's KEY SHARE while a human editor already holds Project.
    account.with_lock('FOR NO KEY UPDATE') do
      command = JrcNico::Command.joins(:session).where(jrc_nico_sessions: { account_id: account.id, user_id: user.id }).find_by(id: command_id)
      raise Rejected unless command

      command.with_lock do
        lock_grants!(account, user)
        validate!(command, account: account, user: user, request: request)
        record_response!(command, yield)
      end
    end
  end

  def self.lock_grants!(account, user)
    # AgentsController updates AccountUser. CustomRolesController updates the
    # role. Keep both grants locked through waits for Project and the effect.
    membership = account.account_users.where(user_id: user.id).lock('FOR SHARE').first
    raise Rejected unless membership

    lock_custom_role!(account, membership.custom_role_id) if membership.custom_role_id.present?
    # Clear association/query-cache reads after taking the grant locks.
    membership.reload
  end

  def self.lock_custom_role!(account, id)
    raise Rejected unless defined?(CustomRole)
    raise Rejected unless CustomRole.where(account_id: account.id).lock('FOR SHARE').find_by(id: id)
  end

  def self.record_response!(command, status)
    raise Rejected unless status.is_a?(Integer) && status.between?(100, 599)

    # A consumed 403 is a denied attempt, never evidence of a successful edit.
    receipt = command.execution_context.fetch(KEY).merge('consumed_at' => Time.current.iso8601(6), 'response_status' => status)
    command.update!(execution_context: command.execution_context.merge(KEY => receipt))
  end

  def self.authorize_browser_result!(command, status)
    return unless command.result['browser_action'] == 'module_action_fenced' && status == 'succeeded'

    raise Pundit::NotAuthorizedError unless successful_receipt?(command.execution_context[KEY])
  end

  def self.successful_receipt?(receipt)
    receipt.is_a?(Hash) && receipt['version'] == VERSION && receipt['consumed_at'].present? &&
      receipt['response_status'].is_a?(Integer) && receipt['response_status'].between?(200, 299)
  end

  def self.validate!(command, account:, user:, request:)
    contract = pending_contract!(command, user)
    access = JrcNico::OperationalAccess.new(account: account, user: user).authorize!
    expected = descriptor(command, access)
    raise Rejected unless contract.except('expires_at') == expected

    validate_request!(request, expected)

    # Includes current capability, tenant, migration acceptance and referenced
    # parent task checks. The native endpoint still applies its own policy/lock.
    JrcNico::ToolExecutor.new(access, command: command).call(command.tool, command.arguments)
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, KeyError, ArgumentError
    raise Rejected
  end

  def self.pending_contract!(command, user)
    contract = command.execution_context[KEY]
    raise Rejected unless contract.is_a?(Hash) && command.status == 'executing' && contract['consumed_at'].nil?
    raise Rejected unless Time.iso8601(contract.fetch('expires_at')) > Time.current

    authorization = command.execution_context['authorization']
    raise Rejected unless authorization.is_a?(Hash) && authorization.values_at('source', 'user_id') == ['operator', user.id]

    contract
  end

  def self.validate_request!(request, expected)
    raise Rejected unless request.request_method == expected['method'] && request.path == expected['path'] && request.query_string.empty?
    raise Rejected unless JrcServiceDesk::CanonicalJson.digest(request.request_parameters) == expected['body_digest']
  end

  private_class_method :lock_grants!, :lock_custom_role!, :record_response!, :successful_receipt?, :pending_contract!, :validate_request!
end
