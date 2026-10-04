module JrcCrm
  # Creates one implementation project from a won deal/order when explicitly
  # requested. Project creation is best-effort: lack of Projects permission is
  # reported back to Backoffice and never invalidates the commercial sale.
  class OrderImplementationProjectService
    DEFAULT_TASKS = [
      'Kickoff',
      'Levantamento',
      'Configuração',
      'Integrações',
      'Treinamento',
      'Homologação',
      'Go-live'
    ].freeze

    def initialize(order:, actor: nil)
      @order = order
      @actor = actor || order.owner
      @account = order.account
    end

    def call
      return result(nil, nil) unless requested?
      return result(nil, 'Projetos não está habilitado para esta conta.') unless JrcOperations::Access.ready? && JrcOperations::Access.enabled?(@account, 'projects')
      return result(nil, 'O pedido não possui um negócio ganho para vincular ao projeto.') unless @order.deal&.won?

      key = idempotency_key
      existing = JrcProjects::Project.find_by(account_id: @account.id, idempotency_key: key)
      return result(existing, nil) if existing

      membership = @account.account_users.find_by(user_id: @actor&.id)
      unless membership && JrcProjects::Authorization.allowed?(account_user: membership, capability: 'projects.project.create')
        return result(nil, 'O responsável atual não possui permissão para criar o Projeto de Implantação.')
      end

      company = @order.deal.company || @order.contact&.company
      template = implementation_template
      project = JrcProjects::Projects::Create.call(
        account: @account,
        actor: @actor,
        attributes: {
          name: project_name(company),
          description: "Projeto criado automaticamente a partir do pedido #{@order.order_number}.",
          visibility: 'account',
          contact_id: @order.contact_id,
          company_id: company&.id,
          starts_on: Date.current.iso8601,
          due_on: due_on.iso8601,
          priority: normalized_priority
        }.compact,
        template: template,
        idempotency_key: key,
        origin: { deal_id: @order.deal_id },
        correlation_id: "sales-order:#{@order.id}"
      )
      seed_default_tasks!(project) unless template
      project.update!(status: 'active') if project.status == 'planned'
      result(project.reload, nil)
    rescue StandardError => e
      Rails.logger.warn("[JRC CRM] implementation project pending for order=#{@order.id}: #{e.class}: #{e.message}")
      result(nil, e.message)
    end

    private

    def requested?
      ActiveModel::Type::Boolean.new.cast(snapshot[:create_implementation_project])
    end

    def snapshot
      @snapshot ||= (@order.snapshot || {}).with_indifferent_access
    end

    def idempotency_key
      "crm-order-implementation-#{@order.id}"
    end

    def implementation_template
      JrcProjects::ProjectTemplate.where(account_id: @account.id, active: true)
                                  .where('name ILIKE ?', '%implant%')
                                  .order(version: :desc, id: :desc).first
    end

    def project_name(company)
      customer = company&.name.presence || @order.contact&.name.presence || @order.deal&.title || @order.order_number
      "Implantação — #{customer}".truncate(240)
    end

    def due_on
      parsed = Date.iso8601(snapshot[:activation_date].to_s) if snapshot[:activation_date].present?
      parsed || Date.current + [snapshot[:activation_days].to_i, 30].max
    rescue ArgumentError
      Date.current + 30
    end

    def normalized_priority
      value = snapshot[:priority].to_s.downcase
      return 'urgent' if value.in?(%w[urgente urgent])
      return 'high' if value.in?(%w[alta high])
      return 'low' if value.in?(%w[baixa low])

      'medium'
    end

    def seed_default_tasks!(project)
      return if project.tasks.exists?

      column = project.board_columns.order(:position).first!
      DEFAULT_TASKS.each_with_index do |title, index|
        project.tasks.create!(
          account: @account,
          created_by: @actor,
          title: title,
          board_column: column,
          status: column.status_key,
          priority: normalized_priority,
          due_on: project.due_on,
          position: (index + 1) * 1024
        )
      end
    end

    def result(project, warning)
      { project: project, warning: warning }
    end
  end
end
