# frozen_string_literal: true

require 'date'

class JrcServiceDesk::CaseWorkspaceQuery
  FIELDS = %w[unit_id operator_company_id kind page per_page status severity service_id category_id owner_account_user_id query created_from
              created_to requester_id source].freeze
  attr_reader :context, :values, :relation, :paging

  def initialize(context:, parameters:)
    @context = JrcServiceDesk::OperationalContext.new(context)
    Pundit.authorize(@context.to_h, JrcServiceDesk::Incident, :index?)
    @values = JrcServiceDesk::Input.attributes(parameters, FIELDS).reject { |_k, v| v.nil? || v == '' }
    raise ArgumentError, 'Invalid kind' unless %w[incident problem].include?(@values.fetch('kind'))

    @paging = JrcServiceDesk::QueryParameters.new(@values.slice('page', 'per_page'))
    @relation = Pundit.policy_scope!(@context.to_h, JrcServiceDesk::Incident).where(resource_kind: @values['kind'])
    filter!
  end

  def call
    presenter = JrcServiceDesk::CasePresenter.new(context: context)
    rows = relation.includes(:service, :category, { unit: :operator_company }, { owner_membership: { account_user: :user } })
                   .order(created_at: :desc, id: :desc).offset(paging.offset).limit(paging.per_page)
    { kind: values['kind'], items: rows.map { |row| presenter.call(row) },
      meta: { page: paging.page, per_page: paging.per_page, total: relation.count }, metrics: metrics }
  end

  private

  def filter!
    units = context.view_unit_scope
    if values['operator_company_id']
      units = units.where(operator_company_id: JrcServiceDesk::Input.id(values['operator_company_id']))
      raise ActiveRecord::RecordNotFound unless units.exists?
    end
    if values['unit_id']
      unit = units.find(JrcServiceDesk::Input.id(values['unit_id']))
      units = units.where(id: unit.id)
    end
    @relation = relation.where(unit_id: units.select(:id))
    { 'status' => JrcServiceDesk::Incident::STATUSES, 'severity' => %w[low normal high critical] }.each do |key, permitted|
      next unless values[key]
      raise ArgumentError, 'Invalid filter' unless permitted.include?(values[key])

      @relation = relation.where(key => values[key])
    end
    { 'service_id' => JrcServiceDesk::Service, 'category_id' => JrcServiceDesk::Category }.each do |key, model|
      next unless values[key]

      record = model.where(account_id: context.account.id, unit_id: units.select(:id)).find(JrcServiceDesk::Input.id(values[key]))
      @relation = relation.where(key => record.id)
    end
    if values['owner_account_user_id']
      id = JrcServiceDesk::Input.id(values['owner_account_user_id'])
      owners = JrcServiceDesk::UnitMembership.where(account_id: context.account.id, unit_id: units.select(:id), account_user_id: id)
      raise ActiveRecord::RecordNotFound unless owners.exists?

      @relation = relation.where(owner_membership_id: owners.select(:id))
    end
    if values['requester_id'].present? || values['source'].present?
      tickets = Pundit.policy_scope!(context.to_h, JrcServiceDesk::Ticket).where(unit_id: units.select(:id))
      if values['requester_id'].present?
        contact = context.account.contacts.find(JrcServiceDesk::Input.id(values['requester_id']))
        JrcServiceDesk::NativeExecutionContext.with(context.to_h) { Pundit.authorize(context.to_h, contact, :show?) }
        tickets = tickets.where(requester_id: contact.id)
      end
      if values['source'].present?
        raise ArgumentError unless values['source'].is_a?(String) && values['source'].length.between?(1, 40)

        tickets = tickets.where(origin_channel: values['source'])
      end
      links = JrcServiceDesk::CaseLink.active.where(account_id: context.account.id, unit_id: units.select(:id), ticket_id: tickets.select(:id))
      legacy_ids = tickets.where.not(incident_id: nil).select(:incident_id)
      incident_ids = JrcServiceDesk::Incident.where(id: links.select(:incident_id)).or(JrcServiceDesk::Incident.where(id: legacy_ids)).select(:id)
      if values['kind'] == 'problem'
        problem_links = JrcServiceDesk::CaseLink.active.where(account_id: context.account.id, unit_id: units.select(:id),
                                                              related_incident_id: incident_ids)
        @relation = relation.where(id: incident_ids).or(relation.where(id: problem_links.select(:incident_id)))
      else
        @relation = relation.where(id: incident_ids)
      end
    end
    dates = %w[created_from created_to].to_h do |key|
      value = values[key]
      raise ArgumentError, 'Date format required' if value && !(value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/))

      [key, value ? Date.iso8601(value) : nil]
    end
    raise ArgumentError, 'Invalid period' if dates.values.all? && dates['created_from'] > dates['created_to']

    dates.each do |key, date|
      next unless date

      date += 1 if key == 'created_to'
      @relation = relation.where("jrc_service_desk_incidents.created_at #{key == 'created_from' ? '>=' : '<'} ?",
                                 Time.utc(date.year, date.month, date.day))
    end
    query = values['query']
    return unless query
    raise ArgumentError, 'Invalid search' unless query.is_a?(String) && query.length <= 200

    term = "%#{ActiveRecord::Base.sanitize_sql_like(query.strip)}%"
    matches = relation.where('title ILIKE :q OR description ILIKE :q', q: term)
    number = query.strip.match(/\A(?:(?:INC|PRB)-|#)?0*([1-9]\d{0,18})\z/i)
    matches = matches.or(relation.where(id: JrcServiceDesk::Input.id(number[1]))) if number
    @relation = matches
  end

  def metrics
    by_status = relation.group(:status).count
    completed = relation.where(status: %w[resolved closed]).where.not(resolved_at: nil).where('resolved_at >= started_at')
    average = completed.average(Arel.sql('EXTRACT(EPOCH FROM (resolved_at - started_at))'))
    { total: relation.count, critical: relation.where(severity: 'critical').count,
      active: relation.where(status: JrcServiceDesk::IncidentWorkflow::ACTIVE).count,
      resolved: by_status.fetch('resolved', 0), closed: by_status.fetch('closed', 0),
      resolution_average_seconds: average&.to_f, resolution_sample_size: completed.count,
      by_status: by_status, by_severity: relation.group(:severity).count,
      timezone: 'UTC', period_basis: 'created_at', duration_basis: 'elapsed_to_last_resolution_not_sla',
      scope: 'authorized_filtered_records_before_pagination' }
  end
end
