# frozen_string_literal: true

class JrcServiceDesk::PublishNotificationPolicyService < JrcServiceDesk::BaseService
  FIELDS = %w[event_type channel enabled inbox_id template template_version confirmed expected_version ticket_type_id service_id display_name
              description settings channel_configurations expected_versions retired_channels].freeze

  def validate_for_preview!(unit:, attributes:)
    @context = fresh_context!
    raise Pundit::NotAuthorizedError unless context.unit_allowed?(unit) && context.capability?(:notifications_manage)

    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    validate_confirmation!(values)
    validate_controls!(values, unit)
    inbox = native_inbox(values)
    fields = values.except('confirmed', 'expected_version', 'inbox_id')
    %w[ticket_type_id service_id].each do |field|
      next unless values[field]

      model = field == 'service_id' ? JrcServiceDesk::Service : JrcServiceDesk::TicketType
      model.where(account: context.account, unit: unit).find(JrcServiceDesk::Input.id(values[field]))
    end
    latest = JrcServiceDesk::NotificationPolicyVersion.where(account: context.account, unit: unit,
      event_type: values['event_type'], channel: values['channel'], ticket_type_id: values['ticket_type_id'], service_id: values['service_id']).maximum(:version).to_i
    actor = context.actor_for(unit)
    candidate = JrcServiceDesk::NotificationPolicyVersion.new(fields.merge(account: context.account, unit: unit, inbox: inbox,
      published_by_membership: actor, version: latest + 1, digest: JrcServiceDesk::CanonicalJson.digest(fields)))
    raise ActiveRecord::RecordInvalid, candidate unless candidate.valid?

    true
  end

  def call(unit_id:, attributes:)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    validate_confirmation!(values)
    %w[display_name description].each do |field|
      next unless values.key?(field)
      raise ArgumentError, 'Presentation metadata must be text' unless values[field].is_a?(String)
    end
    with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:notifications_manage)

      { 'ticket_type_id' => JrcServiceDesk::TicketType, 'service_id' => JrcServiceDesk::Service }.each do |name, model|
        next unless values.key?(name)

        scope = model.where(account_id: context.account.id, unit_id: unit.id)
        scope = scope.where(active: true) if values['enabled']
        values[name] = values[name].nil? ? nil : scope.find(JrcServiceDesk::Input.id(values[name])).id
      end
      validate_controls!(values, unit)
      values.key?('channel_configurations') ? publish_group(unit, values) : publish(unit, values, native_inbox(values))
    end
  end

  private

  def publish_group(unit, values)
    settings = values.fetch('settings')
    order = settings.fetch('channel_order')
    configurations = JrcServiceDesk::Input.attributes(values.fetch('channel_configurations'), %w[email whatsapp])
    expected = JrcServiceDesk::Input.attributes(values.fetch('expected_versions'), %w[email whatsapp])
    retired = values.fetch('retired_channels', [])
    raise ArgumentError unless retired.is_a?(Array) && retired.uniq == retired && (retired - %w[email whatsapp]).empty? && (retired & order).empty?
    raise ArgumentError unless configurations.keys.sort == order.sort && expected.keys.sort == (order + retired).sort

    retired.each do |channel|
      previous = JrcServiceDesk::NotificationPolicyVersion.where(account: context.account, unit: unit,
                                                                 event_type: values.fetch('event_type'), channel: channel, ticket_type_id: values['ticket_type_id'], service_id: values['service_id']).order(version: :desc).first!
      individual = previous.attributes.slice('event_type', 'channel', 'inbox_id', 'template', 'template_version', 'ticket_type_id', 'service_id', 'display_name', 'description', 'settings')
                           .merge('enabled' => false, 'expected_version' => expected.fetch(channel))
      publish(unit, individual, previous.inbox)
    end

    rows = order.map do |channel|
      cfg = JrcServiceDesk::Input.attributes(configurations.fetch(channel), %w[inbox_id template template_version])
      raise ArgumentError unless cfg.keys.sort == %w[inbox_id template template_version].sort

      individual = values.except('channel_configurations', 'expected_versions', 'retired_channels').merge(cfg).merge('channel' => channel,
                                                                                                                     'expected_version' => expected.fetch(channel))
      publish(unit, individual, native_inbox(individual))
    end
    rows.find { |row| row.channel == values['channel'] } || rows.first
  end

  def validate_controls!(values, unit)
    return unless values.key?('settings')

    controls = JrcServiceDesk::NotificationControls.new(values['settings'])
    contacts = context.account.contacts.where(id: controls.settings.fetch('additional_contact_ids', []))
    raise ActiveRecord::RecordNotFound unless contacts.count == controls.settings.fetch('additional_contact_ids', []).size

    contacts.each { |contact| JrcServiceDesk::NativeExecutionContext.with(context.to_h) { authorize!(contact, :show?) } }
    ids = controls.settings.fetch('internal_copy_member_ids', [])
    raise ActiveRecord::RecordNotFound unless context.account.account_users.where(id: ids).count == ids.size

    conditions = controls.settings.dig('conditions', 'items') || []
    models = { 'priority_id' => JrcServiceDesk::Priority, 'queue_id' => JrcServiceDesk::Queue, 'status_id' => JrcServiceDesk::TicketStatus,
               'ticket_type_id' => JrcServiceDesk::TicketType, 'service_id' => JrcServiceDesk::Service, 'category_id' => JrcServiceDesk::Category }
    conditions.each do |item|
      next if item['field'] == 'origin_channel'

      models.fetch(item['field']).where(account_id: context.account.id, unit_id: unit.id).find(JrcServiceDesk::Input.id(item['value']))
    end
  end

  def validate_confirmation!(values)
    valid = values['confirmed'] == true && [true, false].include?(values['enabled'])
    raise ArgumentError, 'Explicit confirmation and enabled state required' unless valid
  end

  def native_inbox(values)
    inbox = values['inbox_id'] && context.account.inboxes.find(JrcServiceDesk::Input.id(values['inbox_id']))
    JrcServiceDesk::NativeExecutionContext.with(context.to_h) { authorize!(inbox, :show?) } if inbox
    valid = inbox && JrcServiceDesk::NotificationEngine.channel(inbox) == values['channel']
    raise ArgumentError, 'Configured native channel required' if values['enabled'] && !valid

    inbox
  end

  def publish(unit, values, inbox)
    event_type = values.fetch('event_type', 'customer_interaction')
    fields = values.except('confirmed', 'inbox_id', 'expected_version', 'channel_configurations', 'expected_versions', 'retired_channels').merge(
      'event_type' => event_type, 'inbox_id' => inbox&.id
    )
    versions = JrcServiceDesk::NotificationPolicyVersion.where(account: context.account, unit: unit,
                                                               event_type: event_type, channel: values.fetch('channel'),
                                                               ticket_type_id: values['ticket_type_id'], service_id: values['service_id'])
    latest = versions.order(version: :desc).first
    current = latest&.version.to_i
    # A legacy editor must not erase presentation metadata on its next publication.
    %w[display_name description settings].each do |field|
      fields[field] = latest.public_send(field) if latest && !values.key?(field)
    end
    configured = fields.dig('settings', 'whatsapp_template')
    if fields['channel'] == 'whatsapp' && configured.present? && fields['enabled']
      JrcServiceDesk::NotificationWhatsappTemplate.new(inbox: inbox, configuration: configured).validate!
    end
    if values.key?('expected_version') && current != JrcServiceDesk::Input.version(values['expected_version'])
      raise JrcServiceDesk::IdempotencyConflict
    end

    JrcServiceDesk::NotificationPolicyVersion.create!(fields.merge(account: context.account, unit: unit,
                                                                   published_by_membership: actor_membership, version: current + 1,
                                                                   digest: JrcServiceDesk::CanonicalJson.digest(fields)))
  end
end
