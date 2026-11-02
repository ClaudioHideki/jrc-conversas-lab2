# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::CaseWorkspacesController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  rescue_from ArgumentError, with: :case_invalid
  rescue_from ::JrcProjects::Errors::WipLimit do
    render json: { code: 'project_wip_limit', error: 'O limite de tarefas da coluna foi atingido. Revise o quadro de Projetos.' },
           status: :unprocessable_entity
  end
  rescue_from ::JrcServiceDesk::AttachmentScanError do
    render json: { code: 'attachment_scan_unavailable', error: 'O arquivo aguarda verificação de segurança.' }, status: :conflict
  end
  rescue_from ::JrcApprovals::Error do
    render json: { code: 'approval_unavailable', error: 'Revise a política publicada, seu escopo e a autorização na Central de Aprovações.' },
           status: :unprocessable_entity
  end

  def index
    authorize ::JrcServiceDesk::Incident, :index?
    policy_scope(::JrcServiceDesk::Incident)
    payload = ::JrcServiceDesk::CaseWorkspaceQuery.new(context: pundit_user, parameters: query_values).call
    render json: base_payload.merge(payload)
  end

  def show
    raise ArgumentError unless query_values.empty?

    row = scoped_case
    authorize row, :show?
    render json: base_payload.merge(record: case_presenter.call(row))
  end

  def create
    values = body_values(%w[unit_id record])
    unit = policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Incident.new(account: Current.account, unit: unit), :create?
    row = ::JrcServiceDesk::CreateIncidentService.new(user_context: pundit_user).call(unit_id: unit.id,
                                                                                      attributes: values.fetch('record'), idempotency_key: request.headers['Idempotency-Key'])
    render json: base_payload.merge(applied: true, record: case_presenter.call(row)), status: :created
  end

  def command
    row = scoped_case
    authorize row, :update?
    values = body_values(%w[action attributes expected_lock_version files])
    values['attributes'] = JSON.parse(values['attributes']) if values['attributes'].is_a?(String)
    outcome = ::JrcServiceDesk::CaseCommandService.new(user_context: pundit_user).call(unit_id: row.unit_id, incident_id: row.id,
                                                                                       action: values.fetch('action'), attributes: values.fetch('attributes'), expected_lock_version: values.fetch('expected_lock_version'),
                                                                                       idempotency_key: request.headers['Idempotency-Key'], files: values.fetch('files', []))
    render json: base_payload.merge(applied: true, record: case_presenter.call(outcome[:row]),
                                    receipt: { id: outcome[:entry].id.to_s, action: values['action'], version_after: outcome[:entry].data['version_after'], replayed: outcome[:replayed] })
  rescue JSON::ParserError
    case_invalid(ArgumentError.new('Invalid attributes'))
  end

  def related
    row = scoped_case
    authorize row, :show?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[type linked query page per_page phase source requester_id created_from created_to])
    linked = values.delete('linked')
    raise ArgumentError unless linked.nil? || %w[true false].include?(linked)

    type = values.delete('type')
    if type == 'tickets'
      ticket_scope = linked == 'true' ? ::JrcServiceDesk::CaseAssociations.tickets(row, operational_context) : nil
      requester_id = values.delete('requester_id')
      if requester_id.present?
        contact = Current.account.contacts.find(::JrcServiceDesk::Input.id(requester_id))
        ::JrcServiceDesk::NativeExecutionContext.with(pundit_user) { authorize contact, :show? }
        ticket_scope ||= policy_scope(::JrcServiceDesk::Ticket)
        ticket_scope = ticket_scope.where(requester_id: contact.id)
      end
      query = ::JrcServiceDesk::TicketQuery.new(user_context: pundit_user,
                                                parameters: values.except('query').merge('unit_id' => row.unit_id, 'q' => values['query']), scope: ticket_scope)
      result = query.collection
      items = result[:items].map do |ticket|
        payload = presenter.ticket(ticket)
        payload.merge(linked: ::JrcServiceDesk::CaseAssociations.tickets(row, operational_context).exists?(id: ticket.id))
      end
    elsif type == 'incidents'
      raise ArgumentError if (values.keys - %w[query page per_page]).any?

      scope = if linked == 'true'
                ::JrcServiceDesk::CaseAssociations.related(row,
                                                           operational_context)
              else
                policy_scope(::JrcServiceDesk::Incident).where(unit_id: row.unit_id,
                                                               resource_kind: row.resource_kind == 'problem' ? 'incident' : 'problem')
              end
      if values['query'].present?
        term = values['query']
        raise ArgumentError unless term.is_a?(String) && term.length <= 200

        scope = scope.where('title ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
      end
      result = paginate(scope.order(created_at: :desc, id: :desc), values)
      linked_ids = ::JrcServiceDesk::CaseAssociations.related(row, operational_context).pluck(:id)
      items = result[:items].map { |item| case_presenter.call(item).merge(linked: linked_ids.include?(item.id)) }
    else
      raise ArgumentError
    end
    render json: base_payload.merge(record_id: row.id.to_s, unit_id: row.unit_id.to_s, type: type, items: items, meta: result[:meta])
  end

  def entries
    row = scoped_case
    authorize row, :show?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[page per_page event_type files_only])
    scope = row.incident_entries
    if values['event_type']
      raise ArgumentError unless ::JrcServiceDesk::IncidentEntry::EVENTS.include?(values['event_type'])

      scope = scope.where(event_type: values['event_type'])
    end
    if values['files_only']
      raise ArgumentError unless values['files_only'] == 'true'

      scope = scope.where(event_type: 'attachment_added')
    end
    result = paginate(scope.order(created_at: :desc, id: :desc), values.slice('page', 'per_page'))
    items = result[:items].includes(actor_membership: { account_user: :user }).with_attached_files.map { |entry| case_presenter.entry(entry) }
    render json: base_payload.merge(record_id: row.id.to_s, unit_id: row.unit_id.to_s, items: items, meta: result[:meta])
  end

  def resources
    row = scoped_case
    authorize row, :show?
    raise ArgumentError unless row.resource_kind == 'problem'

    values = ::JrcServiceDesk::Input.attributes(query_values, %w[kind query page per_page linked])
    kind = values.fetch('kind')
    service = ::JrcServiceDesk::CaseNativeResources.new(row: row, context: operational_context)
    relation = service.scope(kind)
    if values['linked'] == 'true'
      field = ::JrcServiceDesk::CaseNativeResources::TARGETS.fetch(kind)
      relation = relation.where(id: row.resource_links.where(active: true).select("#{field}_id"))
    elsif values['linked'] && values['linked'] != 'false'
      raise ArgumentError
    end
    if values['query'].present?
      raise ArgumentError unless values['query'].is_a?(String) && values['query'].length <= 200

      relation = relation.where('title ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(values['query'])}%") if %w[tasks articles].include?(kind)
    end
    result = paginate(relation.order(id: :desc), values.slice('page', 'per_page'))
    render json: base_payload.merge(record_id: row.id.to_s, unit_id: row.unit_id.to_s, kind: kind,
                                    items: result[:items].map { |record|
                                      service.present(kind, record)
                                    }, meta: result[:meta])
  end

  def resource_options
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[project_query project_page])
    row = scoped_case
    authorize row, :show?
    raise ArgumentError unless row.resource_kind == 'problem'

    ctx = operational_context
    project_scope = ::JrcOperations::Access.projects(ctx.account_user)
    if values['project_query'].present?
      term = values['project_query']
      raise ArgumentError unless term.is_a?(String) && term.length <= 200

      project_scope = project_scope.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(term)}%")
    end
    project_page = ::JrcServiceDesk::Input.id(values.fetch('project_page', 1))
    projects_total = project_scope.count
    projects = project_scope.order(:name, :id).offset((project_page - 1) * 20).limit(20).map do |project|
      { id: project.id.to_s, name: project.name, can_create: ::JrcProjects::Authorization.allowed?(account_user: ctx.account_user, capability: 'projects.task.create', project: project),
        members: project.project_members.includes(:user).map { |member| { id: member.user_id.to_s, name: member.user.name } } }
    end
    can_article = ::JrcServiceDesk::NativeExecutionContext.with(ctx.to_h) { ArticlePolicy.new(ctx.to_h, Article).create? }
    portals = can_article ? ctx.account.portals.order(:name).map { |portal| { id: portal.id.to_s, name: portal.name } } : []
    auth = ::JrcApprovals::Authorization.new(account: ctx.account, user: ctx.user)
    companies = ::JrcCustomers::Company.where(account: ctx.account, active: true, relationship_type: 'internal').filter_map do |company|
      units = ::JrcCrm::BusinessUnit.where(account: ctx.account, company_id: company.id, active: true).filter_map do |unit|
        auth.authorize!('request_create', company_id: company.id, unit_id: unit.id)
        { id: unit.id.to_s, name: unit.name }
      rescue Pundit::NotAuthorizedError
        nil
      end
      company_allowed = begin
        auth.authorize!('request_create', company_id: company.id, unit_id: nil)
        true
      rescue Pundit::NotAuthorizedError
        false
      end
      next if !company_allowed && units.empty?

      { id: company.id.to_s, name: company.name, company_scope_allowed: company_allowed, units: units }
    end
    render json: base_payload.merge(record_id: row.id.to_s, unit_id: row.unit_id.to_s, projects: projects, projects_total: projects_total,
                                    project_page: project_page, portals: portals, approval_companies: companies)
  end

  def attachment
    row = scoped_case
    authorize row, :show?
    raise ArgumentError unless query_values.empty?

    entry = row.incident_entries.find(::JrcServiceDesk::Input.id(params[:entry_id]))
    file = entry.files.find(::JrcServiceDesk::Input.id(params[:attachment_id]))
    info = case_presenter.attachment(entry, file)
    raise ActiveRecord::RecordNotFound if info[:withdrawn]
    unless info[:downloadable]
      return render json: { error: 'O arquivo aguarda a verificação de segurança.', code: 'attachment_scan_unavailable' }, status: :conflict
    end

    send_data ::JrcServiceDesk::AttachmentScanner.download(file.blob), filename: file.filename.to_s, type: 'application/octet-stream',
                                                                       disposition: 'attachment'
  end

  private

  def scoped_case
    policy_scope(::JrcServiceDesk::Incident).find(::JrcServiceDesk::Input.id(params[:case_id]))
  end

  def operational_context
    @operational_context ||= ::JrcServiceDesk::OperationalContext.new(pundit_user)
  end

  def case_presenter
    @case_presenter ||= ::JrcServiceDesk::CasePresenter.new(context: operational_context)
  end

  def paginate(scope, values)
    paging = ::JrcServiceDesk::QueryParameters.new(values.slice('page', 'per_page'))
    { items: scope.offset(paging.offset).limit(paging.per_page), meta: { total: scope.count, page: paging.page, per_page: paging.per_page } }
  end

  def case_invalid(error)
    messages = {
      'No published authorized approval policy' => 'Nenhuma política homologada e publicada se aplica a esta solicitação. Revise a Central de Aprovações.',
      'Resolution summary required' => 'Informe o resumo da solução antes de concluir.',
      'Reopening reason required' => 'Informe o motivo da reabertura.',
      'Invalid state transition' => 'Esta mudança de estado não está disponível. Atualize a consulta.',
      'Reopen the terminal record before editing' => 'O registro está concluído. Reabra com autorização antes de editar.',
      'Title required' => 'Informe o título.', 'Comment required' => 'Escreva o comentário interno.',
      'Upload required' => 'Selecione ao menos um arquivo.', 'Attachment exceeds the supported size' => 'O limite é 20 MB por arquivo.',
      'Attachment already withdrawn' => 'O arquivo já foi retirado. Atualize a consulta.'
    }
    render json: { code: 'invalid_input', error: messages.fetch(error.message, 'Confira os campos, a seleção e o escopo autorizado.') },
           status: :unprocessable_entity
  end
end
