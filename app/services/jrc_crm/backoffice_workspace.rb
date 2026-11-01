module JrcCrm
  # The controller supplies an already authorized relation. Filters can only narrow it.
  class BackofficeWorkspace
    TABLE = 'jrc_crm_backoffice_requests'.freeze
    SORTS = {
      'recent' => "#{TABLE}.created_at DESC, #{TABLE}.id DESC",
      'oldest' => "#{TABLE}.created_at ASC, #{TABLE}.id ASC",
      'deadline' => "LEAST(#{TABLE}.sla_due_at, #{TABLE}.due_at, #{TABLE}.stage_due_at, " \
                    "CASE WHEN #{TABLE}.first_action_at IS NULL THEN #{TABLE}.first_action_due_at END) ASC NULLS LAST, #{TABLE}.id ASC",
      'priority' => "CASE #{TABLE}.priority WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END, #{TABLE}.id ASC"
    }.freeze
    AREAS = {
      'process' => %w[request analysis], 'docs' => %w[documentation contract], 'contracts' => %w[contract],
      'implement' => %w[implementation], 'provision' => %w[provisioning], 'finance' => %w[finance]
    }.freeze

    def initialize(scope:, user:, params:, account:)
      @scope = params[:view] == 'mine' ? scope.where(owner_id: user.id) : scope
      @params = params
      @account = account
      @companies = JrcCrm::CorporateCoverage.new(account: account, user: user).companies(account.master_companies)
    end

    def call
      filtered = filter(@scope)
      total = filtered.count
      per_page = @params[:per_page].to_i.clamp(1, 50)
      per_page = 20 if @params[:per_page].blank?
      pages = [(total.to_f / per_page).ceil, 1].max
      page = @params[:page].to_i.clamp(1, pages)
      rows = filtered.reorder(Arel.sql(SORTS.fetch(@params[:sort], SORTS['recent'])))
                     .offset((page - 1) * per_page).limit(per_page)
                     .includes(:contact, :owner, :business_unit, :operations_queue, :operations_sla_policy, :sales_order)
      @company_names = @companies.where(id: rows.filter_map { |request| request.contact&.company_id }).pluck(:id, :name).to_h
      {
        data: rows.map { |request| serialize(request) },
        meta: { total: total, page: page, per_page: per_page, pages: pages },
        summary: summary(filtered), options: options
      }
    end

    private

    def filter(scope)
      scope = scope.where(stage: AREAS[@params[:view]]) if AREAS.key?(@params[:view])
      scope = scope.where(request_kind: %w[change cancellation]) if @params[:view] == 'changes'
      scope = scope.where(request_kind: 'approval').or(scope.where(stage: 'approval')) if @params[:view] == 'approvals'
      scope = scope.where(status: %w[blocked waiting_customer]).or(scope.where(stage: 'issues')) if @params[:view] == 'issues'
      scope = overdue(scope) if @params[:view] == 'sla'
      if @params[:company_id].present?
        contacts = @account.contacts.where(company_id: @companies.where(id: @params[:company_id]).select(:id))
        scope = scope.where(contact_id: contacts.select(:id))
      end
      %w[stage priority].each { |key| scope = scope.where(key => @params[key]) if @params[key].present? }
      scope = scope.where(request_kind: @params[:kind]) if @params[:kind].present?
      %w[owner_id operations_queue_id business_unit_id].each do |key|
        scope = scope.where(key => @params[key]) if @params[key].present?
      end
      if @params[:status] == 'active'
        scope = scope.where(status: BackofficeRequest::ACTIVE_STATUSES)
      elsif @params[:status].present?
        scope = scope.where(status: @params[:status])
      end
      scope = overdue(scope) if @params[:overdue] == 'true'
      return scope if @params[:q].blank?

      query = "%#{ActiveRecord::Base.sanitize_sql_like(@params[:q].to_s.first(200))}%"
      company_matches = @companies.where('name ILIKE :q OR trade_name ILIKE :q OR customer_code ILIKE :q', q: query).select(:id)
      matching_contacts = @account.contacts.where(company_id: company_matches).select(:id)
      scope.left_joins(:contact, :sales_order, :owner).where(
        "#{TABLE}.request_number ILIKE :q OR #{TABLE}.title ILIKE :q OR contacts.name ILIKE :q OR " \
        "jrc_crm_sales_orders.order_number ILIKE :q OR users.name ILIKE :q OR #{TABLE}.contact_id IN (:contacts)",
        q: query, contacts: matching_contacts
      )
    end

    def overdue(scope)
      # Paused clocks use their pause instant, matching SlaClock#snapshot.
      scope.where(status: BackofficeRequest::ACTIVE_STATUSES).where(
        "#{TABLE}.due_at < :now OR #{TABLE}.sla_due_at < COALESCE(#{TABLE}.sla_paused_at, :now) OR " \
        "#{TABLE}.stage_due_at < COALESCE(#{TABLE}.sla_paused_at, :now) OR " \
        "(#{TABLE}.first_action_at IS NULL AND #{TABLE}.first_action_due_at < COALESCE(#{TABLE}.sla_paused_at, :now))",
        now: Time.current
      )
    end

    def summary(scope)
      active = scope.where(status: BackofficeRequest::ACTIVE_STATUSES)
      result = {
        total: scope.count, active: active.count, overdue: overdue(scope).count,
        blocked: active.where(status: 'blocked').count,
        waiting_customer: active.where(status: 'waiting_customer').count,
        critical: active.where(priority: 'critical').count,
        completed: scope.where(status: 'completed').count,
        stages: active.group("#{TABLE}.stage").count,
        queues: active.group("#{TABLE}.operations_queue_id").count
      }
      return result unless @params[:view] == 'reports'

      totals = scope.group(:request_kind).count
      late = overdue(scope).group(:request_kind).count
      result.merge(
        average_open_hours: active.average(Arel.sql("EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - #{TABLE}.created_at)) / 3600"))&.round || 0,
        kinds: totals.map { |kind, count| { kind: kind, total: count, overdue: late.fetch(kind, 0) } }
      )
    end

    def options
      {
        queues: JrcOperations::Queue.where(id: @scope.select(:operations_queue_id)).order(:name).limit(100).pluck(:id, :name),
        owners: User.where(id: @scope.select(:owner_id)).order(:name).limit(100).pluck(:id, :name),
        business_units: JrcCrm::BusinessUnit.where(id: @scope.select(:business_unit_id)).order(:name).limit(100).pluck(:id, :name)
      }.transform_values { |rows| rows.map { |id, name| { id: id, name: name } } }
    end

    def serialize(request)
      {
        id: request.id, request_number: request.request_number, title: request.title,
        request_kind: request.request_kind, stage: request.stage, status: request.status, priority: request.priority,
        due_at: request.due_at, created_at: request.created_at, updated_at: request.updated_at,
        contact: request.contact && { id: request.contact.id, name: request.contact.name },
        company: company_for(request),
        order: { id: request.sales_order.id, order_number: request.sales_order.order_number },
        owner: { id: request.owner.id, name: request.owner.name },
        business_unit: request.business_unit && { id: request.business_unit.id, name: request.business_unit.name },
        queue: request.operations_queue && { id: request.operations_queue.id, name: request.operations_queue.name },
        sla: JrcOperations::SlaClock.new(request).snapshot
      }
    end

    def company_for(request)
      id = request.contact&.company_id
      { id: id, name: @company_names[id] } if @company_names.key?(id)
    end
  end
end
