# frozen_string_literal: true

require 'digest'

# Coordinates the six-step workspace with native SurveyAdministration.
# Saving/publishing never enqueues a survey, message or callback.
class JrcRelationship::SurveyModelEditor
  attr_reader :context, :access

  def initialize(context)
    @context = context
    @access = JrcRelationship::SurveyModelAccess.new(context)
  end

  def scope(unit_id)
    unit = access.unit!(unit_id)
    JrcRelationship::SurveyModelDraft.where(account: context.account, unit: unit)
  end

  def find(id, action: 'read')
    row = JrcRelationship::SurveyModelDraft.where(account: context.account).find(id)
    access.authorize!(row, action)
    row
  end

  def save(payload:, id: nil, expected_version: nil)
    validate_draft!(payload)
    unit = access.unit!(payload.fetch('unit_id'))
    raise Pundit::NotAuthorizedError unless unit.operator_company_id.to_s == payload['operator_id'].to_s

    row = if id
            find(id, action: 'edit')
          else
            existing = scope(unit.id).find_by(code: payload['code'])
            if existing
              access.authorize!(existing, 'edit')
              unless existing.creator_id == context.user.id && existing.payload == payload
                raise ActiveRecord::StaleObjectError.new(existing,
                                                         'create')
              end

              return existing
            end
            new_draft(unit, payload)
          end
    row.with_lock do
      access.authorize!(row, 'edit') if row.persisted?
      check_version!(row, expected_version) if row.persisted?
      raise ArgumentError, 'Duplique o modelo para alterar sua unidade ou código.' unless row.unit_id == unit.id && row.code == payload['code']

      enforce_permissions!(row, payload)
      row.payload = payload.deep_dup
      row.save!
      context.audit!(row, after: { code: row.code, unit_id: row.unit_id, version: row.lock_version }, action: 'survey_model_draft_saved')
    end
    row
  rescue ActiveRecord::RecordNotUnique
    prior = scope(unit.id).find_by!(code: payload['code'])
    raise ActiveRecord::StaleObjectError.new(prior, 'create') unless prior.creator_id == context.user.id && prior.payload == payload

    access.authorize!(prior, 'edit')
    prior
  end

  def publish(id:, expected_version:, request_key:)
    row = find(id, action: 'publish')
    key = request_key.to_s
    raise ArgumentError, 'Chave de publicação inválida.' unless key.match?(/\A[a-zA-Z0-9_-]{16,100}\z/)

    row.with_lock do
      access.authorize!(row, 'publish')
      digest = Digest::SHA256.hexdigest(JrcServiceDesk::CanonicalJson.dump(row.payload))
      if row.publication_key == key
        raise ActiveRecord::StaleObjectError.new(row, 'publish') unless row.publication_digest == digest

        next row
      end
      check_version!(row, expected_version)
      validate_publication!(row.payload)
      digest = Digest::SHA256.hexdigest(JrcServiceDesk::CanonicalJson.dump(row.payload))
      definition = persist_definition(row)
      persist_rule(row, definition)
      row.update!(definition: definition, published_payload: row.payload.deep_dup,
                  publication_key: key, publication_digest: digest, published_at: Time.current)
      context.audit!(row, after: { definition_id: definition.id, version: definition.version, unit_id: row.unit_id },
                          action: 'survey_model_published')
    end
    row
  end

  def duplicate(id:)
    source = find(id, action: 'edit')
    raise Pundit::NotAuthorizedError unless access.create?

    payload = source.payload.deep_dup
    payload['name'] = "#{payload['name']} (cópia)".first(120)
    payload['code'] = "copy_#{SecureRandom.hex(8)}"
    payload['active'] = false
    save(payload: payload)
  end

  def deactivate(id:, expected_version:)
    row = find(id, action: 'publish')
    row.with_lock do
      access.authorize!(row, 'publish')
      check_version!(row, expected_version)
      definition = row.definition
      if definition && definition.status != 'archived'
        administration.save(kind: 'definitions', id: definition.id, expected_version: definition.version, attributes: { status: 'archived' })
        JrcRelationship::SurveyRule.where(account: context.account, definition: definition).lock.each do |rule|
          administration.save(kind: 'rules', id: rule.id, expected_version: rule.version, attributes: { active: false })
        end
      end
      row.update!(published_payload: row.published_payload.merge('active' => false), payload: row.payload.merge('active' => false),
                  publication_key: nil, publication_digest: nil)
      context.audit!(row, after: { definition_id: definition&.id, active: false }, action: 'survey_model_deactivated')
    end
    row
  end

  def validate_publication!(payload)
    JrcRelationship::SurveyModelContract.new(payload).validate!
    unit = access.unit!(payload.fetch('unit_id'))
    raise Pundit::NotAuthorizedError unless unit.operator_company_id.to_s == payload['operator_id'].to_s

    validate_native_filters!(payload, unit)
    validate_executor!(payload, unit)
    validate_channels!(payload)
    normalize_templates!(payload)
    window = payload.dig('rules', 'send_window')
    if window && window['enabled'] && !ActiveSupport::TimeZone[window['timezone']]
      fail_step!(3, 'send_window.timezone', 'Fuso horário não reconhecido.')
    end
    true
  end

  def present(row)
    data = row.published_payload.presence || row.payload
    { id: row.id, unit_id: row.unit_id, code: row.code, lock_version: row.lock_version, payload: row.payload,
      definition_id: row.definition_id, published_version: row.definition&.version, published_at: row.published_at&.iso8601,
      publication_key: row.publication_key, active: row.definition&.status == 'active', changed: row.payload != row.published_payload,
      permissions: { edit: access.allowed?(data, 'edit'), publish: access.allowed?(data, 'publish'),
                     duplicate: access.create?, manage_permissions: context.policy.admin? } }
  end

  def options(unit_id)
    unit = access.unit!(unit_id)
    members = context.account.account_users.includes(:user).where(user_id: context.assignable_users.select(:id))
    executors = members.filter_map do |member|
      c = JrcRelationship::Context.new(member)
      op = JrcServiceDesk::OperationalContext.new(c.to_h)
      { id: member.id, name: member.user.name } if c.policy.manage? && op.unit_allowed?(unit) && op.capability?(:tickets_view)
    rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
      nil
    end
    inboxes = assigned_inboxes(context.member).includes(:channel)
    { units: access.units.includes(:operator_company).map do |u|
      { id: u.id, name: u.name, operator_id: u.operator_company_id, operator_name: u.operator_company.name }
    end,
      teams: team_scope.order(:name).map { |team| { id: team.id, name: team.name } },
      queues: choices(JrcServiceDesk::Queue, unit), ticket_types: choices(JrcServiceDesk::TicketType, unit), priorities: choices(JrcServiceDesk::Priority, unit),
      executors: executors, inboxes: inboxes.filter_map { |inbox| inbox_choice(inbox) },
      automation_enabled: JrcRelationship::SurveyEngine.enabled?(context.account),
      can_create: access.create?, can_configure: context.policy.configure?, role: access.role,
      timezone: (Time.find_zone(context.account.reporting_timezone) || Time.zone).tzinfo.name,
      unsupported_channels: %w[sms ivr] }
  end

  private

  def team_scope
    rows = context.account.teams
    context.policy.admin? ? rows : rows.where(id: TeamMember.where(user_id: context.user.id).select(:team_id))
  end

  def new_draft(unit, payload)
    raise Pundit::NotAuthorizedError unless access.create?

    JrcRelationship::SurveyModelDraft.new(account: context.account, unit: unit, creator: context.user, code: payload.fetch('code'))
  end

  def validate_draft!(payload)
    unless payload.is_a?(Hash) && (payload.keys - JrcRelationship::SurveyModelContract::TOP_KEYS).empty? && payload.to_json.bytesize <= 100_000
      raise ArgumentError, 'Rascunho inválido ou muito grande.'
    end
    unless payload['name'].is_a?(String) && payload['description'].is_a?(String) && %w[channels rules permissions settings].all? do |key|
      payload[key].is_a?(Hash)
    end && payload['questions'].is_a?(Array)
      raise ArgumentError, 'Estrutura de rascunho incompatível com o editor.'
    end

    valid = payload['kind'].is_a?(String) && [true, false].include?(payload['active'])
    valid &&= payload['channels'].keys.sort == JrcRelationship::SurveyModelContract::CHANNELS.sort
    valid &&= payload['channels'].values.all? { |value| value.is_a?(Hash) && [true, false].include?(value['enabled']) }
    valid &&= payload['questions'].all? { |question| question.is_a?(Hash) && question['key'].is_a?(String) && question['text'].is_a?(String) }
    valid &&= %w[team_ids edit_roles publish_roles response_roles report_roles].all? { |key| payload['permissions'][key].is_a?(Array) }
    valid &&= payload['rules']['send_window'].is_a?(Hash)
    raise ArgumentError, 'O rascunho pode estar incompleto, mas seus campos devem manter os formatos do editor.' unless valid

    raise ArgumentError, 'Código inválido.' unless payload['code'].to_s.match?(/\A[a-z0-9_-]{1,32}\z/)
  end

  def enforce_permissions!(row, payload)
    return if context.policy.admin?

    original = row.published_payload.presence || row.payload
    raise Pundit::NotAuthorizedError unless original['permissions'] == payload['permissions']
  end

  def check_version!(row, version)
    return if version.to_s.match?(/\A\d+\z/) && row.lock_version.to_s == version.to_s

    raise ActiveRecord::StaleObjectError.new(row, 'update')
  end

  def validate_native_filters!(payload, unit)
    rules = payload.fetch('rules')
    { 'queue_id' => JrcServiceDesk::Queue, 'priority_id' => JrcServiceDesk::Priority,
      'ticket_type_id' => JrcServiceDesk::TicketType }.each do |key, model|
      fail_step!(3, key, 'Filtro indisponível nesta unidade.') if rules[key].present? && !model.exists?(account_id: context.account.id,
                                                                                                        unit_id: unit.id, active: true, id: rules[key])
    end
    ids = Array(payload.dig('permissions', 'team_ids')).map(&:to_s)
    ids << rules['team_id'].to_s if rules['team_id'].present?
    fail_step!(4, 'team_ids', 'Equipe fora do escopo autorizado.') unless team_scope.where(id: ids).count == ids.uniq.size
  end

  def validate_executor!(payload, unit)
    member = context.account.account_users.find(payload.dig('rules', 'execution_member_id'))
    fail_step!(3, 'execution_member_id', 'Executor não autorizado.') unless context.assignable_users.exists?(id: member.user_id)
    executor = JrcRelationship::Context.new(member)
    sd = JrcServiceDesk::OperationalContext.new(executor.to_h)
    return if executor.policy.manage? && sd.unit_allowed?(unit) && sd.capability?(:tickets_view)

    fail_step!(3, 'execution_member_id',
               'O executor precisa de acesso operacional à unidade e ao motor de pesquisas.')
  end

  def validate_channels!(payload)
    executor = context.account.account_users.find(payload.dig('rules', 'execution_member_id'))
    payload.fetch('channels').each do |channel, cfg|
      next unless cfg['enabled'] && channel != 'public_link'

      inbox = assigned_inboxes(context.member).find_by(id: cfg['inbox_id'])
      unless inbox && assigned_inboxes(executor).exists?(id: inbox.id) && inbox_choice(inbox)&.dig(:channel) == channel
        fail_step!(2, channel, 'A caixa deve estar disponível para você e para o executor.')
      end
    end
  end

  def normalize_templates!(payload)
    config = payload.dig('channels', 'whatsapp')
    return unless config && config['enabled'] && config['whatsapp_template']

    rule = JrcRelationship::SurveyRule.new(account: context.account, execution_member_id: payload.dig('rules', 'execution_member_id'),
                                           settings: { 'channel' => 'whatsapp', 'delivery_inbox_id' => config['inbox_id'], 'whatsapp_template' => config['whatsapp_template'] })
    JrcRelationship::SurveyRuleTemplate.new(rule).normalize!
    config['whatsapp_template'] = rule.settings['whatsapp_template']
  rescue ArgumentError, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    fail_step!(2, 'whatsapp_template', 'Selecione novamente um template aprovado com o link da pesquisa.')
  end

  # The native inbox rule uses AccountUser.role and InboxMember. Resolve both
  # explicitly: User#assigned_inboxes depends on the request's Current.account,
  # which may be absent or belong to the configurator rather than the executor.
  def assigned_inboxes(member)
    raise Pundit::NotAuthorizedError unless member.account_id == context.account.id

    rows = context.account.inboxes
    member.administrator? ? rows : rows.where(id: InboxMember.where(user_id: member.user_id).select(:inbox_id))
  end

  def choices(model, unit)
    model.where(account_id: context.account.id, unit_id: unit.id, active: true).order(:name).map { |r| { id: r.id, name: r.name } }
  end

  def inbox_choice(inbox)
    channel = case inbox.channel_type
              when 'Channel::Email' then 'email'
              when 'Channel::Whatsapp' then 'whatsapp'
              when 'Channel::Api' then 'whatsapp' if JrcBroker::OutboundChannel.available?(inbox)
              when 'Channel::TwilioSms' then 'whatsapp' if inbox.twilio_whatsapp?
              end
    { id: inbox.id, name: inbox.name, channel: channel } if channel
  end

  def administration
    @administration ||= JrcRelationship::SurveyAdministration.new(context)
  end

  def persist_definition(row)
    payload = row.payload
    cfg = payload.fetch('settings', {}).except('ces_direction')
    cfg['ces_direction'] = payload.dig('settings', 'ces_direction') if payload['kind'] == 'ces'
    cfg['service_desk_model'] = payload.deep_dup
    attrs = { name: payload['name'], code: "sd_#{row.unit_id}_#{row.code}", kind: payload['kind'],
              status: payload['active'] ? 'active' : 'archived', questions: payload['questions'], settings: cfg }
    administration.save(kind: 'definitions', id: row.definition_id, expected_version: row.definition&.version, attributes: attrs)
  end

  def persist_rule(row, definition)
    data = row.payload
    policy = data.fetch('rules')
    previous = JrcRelationship::SurveyRule.where(account: context.account, definition: definition).first
    channels = data.fetch('channels')
    channel = policy['channel_order'].find { |key| channels.dig(key, 'enabled') == true }
    settings = policy.slice('frequency_days', 'delay_minutes', 'expires_hours', 'consent_required').merge(
      'channel' => channel, 'frequency_scope' => 'contact_type', 'max_attempts' => 1, 'resend_minutes' => 60,
      'delivery_inbox_id' => channels.dig(channel, 'inbox_id'), 'whatsapp_template' => channels.dig(channel, 'whatsapp_template'),
      'service_desk_model' => data.deep_dup
    )
    matchers = { 'source_type' => 'JrcServiceDesk::Ticket', 'unit_id' => row.unit_id }
    matchers['team_id'] = policy['team_id'] if policy['team_id'].present?
    attrs = { name: data['name'], definition_id: definition.id, active: data['active'], priority: policy['priority'],
              execution_member_id: policy['execution_member_id'], matchers: matchers, settings: settings }
    administration.save(kind: 'rules', id: previous&.id, expected_version: previous&.version, attributes: attrs)
  end

  def fail_step!(step, field, message)
    raise JrcRelationship::SurveyModelContract::Invalid.new([{ step: step, field: field, message: message }])
  end
end
