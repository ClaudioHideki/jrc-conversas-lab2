class JrcNico::AnalyzeJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = JrcNico::Run.find_by(id: run_id)
    return unless run

    ledger = JrcNico::ReservationLedger.new(run)
    claimed = run.account.with_lock do
      run.with_lock do
        next false unless run.status == 'queued'

        run.update!(status: 'running', started_at: Time.current)
        ledger.prepare!(kind: 'analysis')
        true
      end
    end
    return unless claimed

    raise Pundit::NotAuthorizedError unless JrcNico::AgentCatalog.for_account(run.account).any? { |agent| agent[:key] == run.agent_key }

    context = JrcNico::ContextBuilder.new(account: run.account, user: run.user, conversation: run.conversation).build(run.message, agent_key: run.agent_key)
    ready = run.with_lock do
      next false unless run.status == 'running'

      run.update!(source_manifest: context.values.flatten.map { |item| item.slice(:source, :reference) })
      true
    end
    return unless ready

    provider = JrcAi::AccountProvider.resolve(run.account) if ENV['NICO_MODE'] == 'provider'
    ledger.prepare!(kind: 'analysis', provider: provider)
    result = JrcNico::RuntimeClient.new(provider: provider, ledger: ledger).analyze(run, context)
    ledger.complete!(result)
  rescue StandardError => e
    Rails.logger.warn("NICO analysis failed run_id=#{run_id} type=#{e.class.name}")
    ledger&.failed!(e) if claimed
  end
end
