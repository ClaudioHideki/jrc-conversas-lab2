class JrcBackoffice::Issues
  TYPES = %w[documentary registration commercial financial legal technical customer seller operational].freeze
  STATUSES = %w[open waiting_third_party resolved canceled].freeze

  def initialize(request:, actor:)
    @request, @actor = request, actor
  end

  def create!(attributes)
    @request.with_lock do
      writable!
      description = attributes[:description].to_s.strip
      raise ArgumentError, 'Descreva a pendência.' if description.blank?

      kind = attributes[:issue_type].presence || 'operational'
      raise ArgumentError, 'Tipo de pendência inválido.' unless TYPES.include?(kind)

      blocking = attributes.key?(:blocking) ? ActiveModel::Type::Boolean.new.cast(attributes[:blocking]) : true
      due_at = parse_time(attributes[:due_at])
      if @request.workflow_version == 2 && blocking && due_at.nil?
        raise ArgumentError, 'Informe o prazo da pendência bloqueante.'
      end
      responsible = attributes[:responsible_id].presence || @request.owner_id
      @request.account.users.find(responsible)
      version = @request.document_versions.find(attributes[:document_version_id]) if attributes[:document_version_id].present?
      data = @request.metadata.deep_dup
      data['issues'] ||= []
      issue = { 'id' => SecureRandom.uuid, 'description' => description, 'type' => kind, 'status' => 'open',
        'blocking' => blocking, 'due_at' => due_at&.iso8601, 'responsible_id' => responsible.to_i,
        'origin_stage' => @request.stage, 'origin_event' => version ? 'document_review' : 'manual',
        'document_version_id' => version&.id, 'created_at' => Time.current.iso8601, 'created_by_id' => @actor.id }
      data['issues'] << issue
      @request.update!(metadata: data, status: blocking ? 'blocked' : @request.status)
      audit!('backoffice_issue_created', {}, issue)
      issue
    end
  end

  def update!(id:, status:, reason:)
    raise ArgumentError, 'Estado de pendência inválido.' unless STATUSES.include?(status)
    raise ArgumentError, 'Informe o motivo do cancelamento.' if status == 'canceled' && reason.to_s.strip.blank?

    @request.with_lock do
      writable!
      data = @request.metadata.deep_dup
      issue = Array(data['issues']).find { |row| row['id'] == id.to_s }
      raise ActiveRecord::RecordNotFound unless issue

      before = issue.deep_dup
      issue.merge!('status' => status, 'resolution' => reason.to_s.first(2000), 'updated_by_id' => @actor.id,
        'updated_at' => Time.current.iso8601)
      if %w[resolved canceled].include?(status)
        issue.merge!('resolved_at' => Time.current.iso8601, 'resolved_by_id' => @actor.id)
      end
      blocking = data['issues'].any? { |row| !%w[resolved canceled].include?(row['status']) && row.fetch('blocking', true) }
      next_status = blocking ? 'blocked' : @request.status
      next_status = 'in_progress' if !blocking && @request.blocked?
      # Keep the origin stage. Resolution never silently skips a workflow step.
      @request.update!(metadata: data, status: next_status)
      audit!('backoffice_issue_resolved', before, issue)
      issue
    end
  end

  private

  def writable!
    raise ArgumentError, 'Reabra a solicitação antes de alterar pendências.' if @request.status.in?(%w[completed canceled rejected])
  end

  def parse_time(value)
    return if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError
    raise ArgumentError, 'Prazo de pendência inválido.'
  end

  def audit!(event, before, after)
    JrcCrm::AuditEvent.create!(account: @request.account, actor_type: 'User', actor_id: @actor.id, event_type: event,
      resource_type: @request.class.name, resource_id: @request.id, from_value: before, to_value: after,
      metadata: { source: 'backoffice_issues', correlation_id: @request.request_number })
  end
end
