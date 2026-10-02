module JrcOperations
  # Read-only projection. Source records remain in CRM and Projects.
  class Agenda
    SOURCES = %w[all crm service_desk projects].freeze
    VIEWS = %w[all open today upcoming overdue completed canceled].freeze
    LIMIT_PER_SOURCE = 1000

    def initialize(account_user:, filters: {}, now: Time.current)
      @member = account_user
      @account = account_user.account
      @filters = filters.to_h.symbolize_keys
      @customer_context = JrcCustomers::AgendaContext.new(account_user: @member, filters: @filters)
      @zone = Time.find_zone(@account.reporting_timezone) || Time.find_zone!('America/Sao_Paulo')
      @now = now.in_time_zone(@zone)
      @today = @now.to_date
      @source = @filters[:source].presence || 'all'
      @view = @filters[:view].presence || 'all'
      raise ArgumentError, 'Origem ou visualizacao invalida.' unless SOURCES.include?(@source) && VIEWS.include?(@view)
      first, last = default_period
      @from = date_filter(:from, first)
      @to = date_filter(:to, last)
      raise ArgumentError, 'Selecione um periodo de ate 366 dias.' if @to < @from || (@to - @from).to_i > 366
      value = @filters[:user_id].presence || @member.user_id
      @responsible = value == 'all' ? nil : @account.users.find(value)
    end

    def call
      entries = []
      entries.concat(project_entries) if source?('projects') && Access.project_access?(@member)
      if source?('crm') && Access.crm?(@member)
        entries.concat(activity_entries)
        entries.concat(follow_up_entries)
      end
      counts = VIEWS.index_with { |view| entries.count { |entry| matches_view?(entry, view) } }
      data = entries.select { |entry| matches_view?(entry, @view) }.sort_by do |entry|
        date_only = entry[:due_type] == 'date'
        [entry[:due_date], date_only ? 0 : 1, date_only ? 0 : Time.iso8601(entry[:due]).to_f, entry[:id]]
      end
      {
        data: data,
        meta: {
          scope: @responsible ? 'assigned_user' : 'accessible_records', user_id: @responsible&.id,
          source: @source, view: @view, from: @from.iso8601, to: @to.iso8601,
          today: @today.iso8601, now: @now.iso8601, time_zone: @zone.tzinfo.name,
          limit_per_source: LIMIT_PER_SOURCE, counts: counts,
          unavailable_sources: { service_desk: 'native_tasks_not_available' },
          # Same account user directory already exposed by operations/options.
          users: @account.users.order('users.name').limit(1000).pluck('users.id', 'users.name').map { |id, name| { id: id, name: name } }
        }
      }
    end

    private

    def default_period
      case @view
      when 'today' then [@today, @today]
      when 'upcoming' then [@today, @today + 30]
      when 'overdue' then [@today - 366, @today]
      else [@today.beginning_of_month, @today.end_of_month]
      end
    end

    def date_filter(key, fallback)
      return fallback if @filters[key].blank?
      value = @filters[key].to_s
      raise ArgumentError, 'Data invalida: use AAAA-MM-DD.' unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(value)
    end

    def source?(name)
      @source == 'all' || @source == name
    end

    def assigned(scope, column)
      # Reject malformed legacy assignments as well as foreign filter IDs.
      valid = scope.where(column => @account.users.select(:id)).or(scope.where(column => nil))
      @responsible ? valid.where(column => @responsible.id) : valid
    end

    def timed(scope)
      # Half-open local-day bounds preserve timezone and DST without inventing times.
      start_at = @zone.local(@from.year, @from.month, @from.day)
      next_date = @to + 1
      end_at = @zone.local(next_date.year, next_date.month, next_date.day)
      scope.where(due_at: start_at...end_at)
    end

    def rows(scope)
      records = scope.limit(LIMIT_PER_SOURCE + 1).to_a
      raise ArgumentError, 'Mais de 1000 compromissos em uma origem: reduza o periodo ou filtre o responsavel.' if records.size > LIMIT_PER_SOURCE
      records
    end

    def project_entries
      scope = JrcProjects::Task.where(account_id: @account.id, project_id: @customer_context.projects(Access.projects(@member)).select(:id), due_on: @from..@to)
      scope = assigned(scope, :assignee_id)
      scope = scope.where(parent_id: nil).or(scope.where.not(assignee_id: nil))
      rows(scope.includes(:project, :assignee)).filter_map do |task|
        next unless JrcProjects::Authorization.allowed?(account_user: @member, capability: 'projects.task.view', project: task.project, record: task)
        entry(task, kind: 'project_task', source: 'projects', due: task.due_on, date_only: true, responsible: task.assignee)
          .merge(project_id: task.project_id, task_id: task.id, parent_id: task.parent_id, project_key: task.project.key)
      end
    end

    def crm_scope(model)
      scope = model.where(account_id: @account.id)
      # Match ActivitiesController / FollowUpsController visible_to_current_user.
      scope = scope.where(user_id: @member.user_id) unless Access.admin?(@member)
      scope = assigned(scope, :user_id)
      scope = scope.where(deal_id: nil).or(scope.where(deal_id: JrcCrm::Deal.where(account_id: @account.id).select(:id)))
      scope = scope.where(lead_id: nil).or(scope.where(lead_id: JrcCrm::Lead.where(account_id: @account.id).select(:id)))
      @customer_context.crm(timed(scope)).includes(:user)
    end

    def activity_entries
      rows(crm_scope(JrcCrm::Activity)).map do |activity|
        entry(activity, kind: 'crm_activity', source: 'crm', due: activity.due_at, responsible: activity.user,
              completed: activity.completed_at.present?).merge(activity_id: activity.id, activity_type: activity.activity_type)
      end
    end

    def follow_up_entries
      rows(crm_scope(JrcCrm::FollowUp)).map do |follow_up|
        completed = follow_up.is_completed? || follow_up.completed_at.present?
        entry(follow_up, kind: 'crm_follow_up', source: 'crm', due: follow_up.due_at, responsible: follow_up.user,
              completed: completed).merge(follow_up_id: follow_up.id, activity_type: 'follow_up')
      end
    end

    def entry(record, kind:, source:, due:, responsible:, date_only: false, completed: false)
      status = record.respond_to?(:status) ? record.status : (completed ? 'completed' : 'scheduled')
      canceled = %w[canceled cancelled].include?(status)
      completed = !canceled && (completed || status == 'completed')
      local_due = date_only ? due : due.in_time_zone(@zone)
      overdue = !completed && !canceled && (date_only ? due < @today : due < @now)
      {
        id: "#{kind}:#{record.id}", kind: kind, source: source, title: record.title, status: status,
        due: local_due.iso8601, due_date: local_due.to_date.iso8601, due_type: date_only ? 'date' : 'datetime',
        responsible_id: responsible&.id, responsible: responsible&.name,
        completed: completed, canceled: canceled, overdue: overdue
      }.merge(@customer_context.attributes(record))
    end

    def matches_view?(entry, view)
      open = !entry[:completed] && !entry[:canceled]
      case view
      when 'all' then true
      when 'open' then open
      when 'today' then open && entry[:due_date] == @today.iso8601
      when 'upcoming' then open && !entry[:overdue]
      when 'overdue' then entry[:overdue]
      when 'completed' then entry[:completed]
      when 'canceled' then entry[:canceled]
      end
    end
  end
end
