module JrcOperations
  class BackofficeRouter
    Result = Struct.new(:queue, :policy, :owner, keyword_init: true)

    def initialize(account:, order:, request_kind:, priority:, preferred_owner: nil)
      @account = account
      @order = order
      @request_kind = request_kind.to_s
      @priority = priority.to_s
      @preferred_owner = preferred_owner
    end

    def call
      queue = matching_queue || ensure_default_queue!
      policy = matching_policy(queue) || ensure_default_policy!(queue)
      Result.new(queue: queue, policy: policy, owner: resolve_owner(queue))
    end

    private

    def matching_queue
      JrcOperations::Queue.active.where(account_id: @account.id)
                          .order(Arel.sql("CASE WHEN code = 'BACKOFFICE-GERAL' THEN 1 ELSE 0 END, business_unit_id NULLS LAST, id ASC"))
                          .detect { |queue| queue.matches?(order: @order, request_kind: @request_kind, priority: @priority) }
    end

    def matching_policy(queue)
      JrcOperations::SlaPolicy.active.where(account_id: @account.id, scope_kind: 'backoffice')
                              .order(Arel.sql("CASE WHEN conditions @> '{\"monitor_only\":true}'::jsonb THEN 1 ELSE 0 END, operations_queue_id NULLS LAST, id ASC"))
                              .detect { |policy| policy.matches?(order: @order, request_kind: @request_kind, priority: @priority, queue: queue) }
    end

    def ensure_default_queue!
      JrcOperations::Queue.find_or_create_by!(account_id: @account.id, code: 'BACKOFFICE-GERAL') do |queue|
        queue.name = 'Backoffice Geral'
        queue.assignment_strategy = 'manual'
        queue.active = true
        queue.settings = { 'system_default' => true }
      end
    end

    def ensure_default_policy!(queue)
      name = queue.code == 'BACKOFFICE-GERAL' ? 'Backoffice — configurar SLA' : "Backoffice — configurar SLA — #{queue.code}"
      JrcOperations::SlaPolicy.find_or_create_by!(account_id: @account.id, scope_kind: 'backoffice',
                                                  operations_queue_id: queue.id, name: name) do |policy|
        policy.active = true
        policy.conditions = { 'system_default' => true, 'monitor_only' => true }
        policy.business_hours = { 'enabled' => false }
        policy.pause_statuses = ['waiting_customer']
        policy.alert_thresholds = [50, 75, 90, 100]
      end
    end

    def resolve_owner(queue)
      configured_user_ids = Array((queue.settings || {})['user_ids']).map(&:to_i).reject(&:zero?)
      if queue.assignment_strategy == 'manual'
        return queue.candidate_users.find_by(id: configured_user_ids.first) if configured_user_ids.any?
        return @preferred_owner if @preferred_owner
      end

      users = queue.candidate_users.to_a
      return @preferred_owner || @order.owner if users.empty?

      case queue.assignment_strategy
      when 'least_load'
        active_statuses = JrcCrm::BackofficeRequest::ACTIVE_STATUSES
        counts = JrcCrm::BackofficeRequest.where(account_id: @account.id, operations_queue_id: queue.id,
                                                  owner_id: users.map(&:id), status: active_statuses).group(:owner_id).count
        users.min_by { |user| [counts[user.id].to_i, user.id] }
      when 'round_robin'
        last_by_user = JrcCrm::BackofficeRequest.where(account_id: @account.id, operations_queue_id: queue.id,
                                                        owner_id: users.map(&:id)).group(:owner_id).maximum(:created_at)
        users.min_by { |user| [last_by_user[user.id] || Time.at(0), user.id] }
      when 'specialty'
        preferred_ids = Array((queue.settings || {})['specialty_user_ids']).map(&:to_i)
        users.find { |user| preferred_ids.include?(user.id) } || @preferred_owner || users.first
      else
        @preferred_owner || @order.owner || users.first
      end
    end
  end
end
