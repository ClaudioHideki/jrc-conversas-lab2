class JrcNico::RunCapacity
  class Exceeded < StandardError
    MESSAGES = {
      'monthly_token_limit' => 'O limite mensal de tokens do NICO desta conta foi atingido.',
      'monthly_execution_limit' => 'O limite mensal de execuções do NICO desta conta foi atingido.',
      'concurrency_limit' => 'O NICO atingiu a concorrência máxima desta conta. Aguarde as operações em andamento.',
      'conversation_busy' => 'Já existe uma análise em andamento nesta conversa.',
      'reservation_reconciliation_required' => 'Há consumo incerto reservado nesta conta. O administrador deve revisar as reservas antes de liberar capacidade.'
    }.freeze
    attr_reader :code

    def initialize(code = 'concurrency_limit')
      @code = code
      super(MESSAGES.fetch(code))
    end

    def user_message
      message
    end
  end

  # Call while holding the account lock, in the transaction that creates the run.
  def self.reservation_for!(account, conversation: nil, reservation_tokens: 270_000)
    JrcNico::ReservationReconciler.new(account: account).call(dry_run: false)
    capacity = snapshot(account)
    reservation = ENV['NICO_MODE'] == 'provider' ? reservation_tokens.clamp(1, 270_000) : 0
    raise Exceeded, 'monthly_execution_limit' if capacity[:executions] >= capacity[:execution_limit]
    raise Exceeded, 'concurrency_limit' if capacity[:active_operations] >= capacity[:concurrency_limit]
    raise Exceeded, 'conversation_busy' if conversation && live_runs(account).where(conversation: conversation).exists?
    if capacity[:used_tokens] + capacity[:reserved_tokens] + reservation > capacity[:token_limit]
      code = capacity[:uncertain_tokens].positive? && capacity[:used_tokens] + reservation <= capacity[:token_limit] ?
               'reservation_reconciliation_required' : 'monthly_token_limit'
      raise Exceeded, code
    end

    reservation
  end

  def self.snapshot(account)
    account.with_lock { locked_snapshot(account) }
  end

  def self.locked_snapshot(account)
    runs = JrcNico::Run.where(account: account, created_at: Time.current.all_month)
    operations = JrcNico::Inference.where(account: account, created_at: Time.current.all_month)
    run_holds = without_receipt(runs)
    operation_holds = without_receipt(operations)
    reserved = run_holds.sum(:reserved_tokens) + operation_holds.sum(:reserved_tokens)
    used = account.jrc_ai_usage_events.current_month.where(agent_key: JrcNico::AgentCatalog::KEYS).sum(:total_tokens)
    live = live_runs(account).count + live_inferences(account).count
    token_limit = account.custom_attributes.fetch('nico_monthly_token_limit', 1_000_000).to_i
    active_tokens = without_receipt(live_runs(account).merge(runs)).sum(:reserved_tokens) +
                    without_receipt(live_inferences(account).merge(operations)).sum(:reserved_tokens)
    { token_limit: token_limit, execution_limit: account.custom_attributes.fetch('nico_monthly_run_limit', 1000).to_i,
      concurrency_limit: account.custom_attributes.fetch('nico_concurrency', 3).to_i.clamp(1, 8),
      used_tokens: used, reserved_tokens: reserved, uncertain_tokens: reserved - active_tokens,
      remaining_tokens: [token_limit - used - reserved, 0].max, active_operations: live,
      executions: [runs, operations].sum { |scope| scope.where("COALESCE(accounting ->> 'basis', '') <> 'not_executed'").count } }
  end

  def self.live_runs(account)
    JrcNico::Run.where(account: account).where(
      "(status = 'queued' AND created_at > ?) OR (status = 'running' AND COALESCE(lease_expires_at, COALESCE(started_at, created_at) + INTERVAL '3 minutes') > ?)",
      JrcNico::ReservationLedger::QUEUE_TTL.ago, Time.current
    )
  end

  def self.live_inferences(account)
    JrcNico::Inference.where(account: account, status: 'running')
           .where("COALESCE(lease_expires_at, created_at + INTERVAL '3 minutes') > ?", Time.current)
  end

  def self.without_receipt(scope)
    scope.where("NOT #{JrcNico::ReservationLedger.receipt_condition(scope.klass)}")
  end
  private_class_method :without_receipt
  private_class_method :locked_snapshot
end
