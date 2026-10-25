# frozen_string_literal: true

class JrcServiceDesk::NotificationControls
  FIELDS = %w[conditions channel_order multichannel_mode additional_contact_ids internal_copy_member_ids window outside_window max_attempts
              backoff_minutes].freeze
  CONDITION_FIELDS = %w[ticket_type_id service_id priority_id queue_id status_id category_id origin_channel].freeze
  OPTIONAL_FIELDS = %w[copy_assignee whatsapp_template].freeze
  attr_reader :settings

  def initialize(settings)
    @settings = JrcServiceDesk::Input.attributes(settings, FIELDS + OPTIONAL_FIELDS)
    validate! unless settings.empty?
  end

  def validate!
    raise ArgumentError unless (settings.keys - OPTIONAL_FIELDS).sort == FIELDS.sort
    raise ArgumentError if settings.key?('copy_assignee') && ![true, false].include?(settings['copy_assignee'])

    if settings['whatsapp_template'].present?
      data = JrcServiceDesk::Input.attributes(settings['whatsapp_template'], %w[inbox_id params fingerprint])
      raise ArgumentError unless data.keys.sort == %w[inbox_id params fingerprint].sort
    end
    raise ArgumentError unless %w[first_available all_explicit].include?(settings['multichannel_mode'])

    order = settings['channel_order']
    raise ArgumentError unless order.is_a?(Array) && order.any? && order.uniq == order && (order - %w[whatsapp email]).empty?

    %w[additional_contact_ids internal_copy_member_ids].each do |key|
      values = settings[key]
      raise ArgumentError unless values.is_a?(Array) && values.size <= 20

      settings[key] = values.map { |id| JrcServiceDesk::Input.id(id) }.uniq
    end
    condition = JrcServiceDesk::Input.attributes(settings['conditions'], %w[operator items])
    raise ArgumentError unless %w[all any].include?(condition['operator']) && condition['items'].is_a?(Array) && condition['items'].size <= 20

    condition['items'].each do |item|
      data = JrcServiceDesk::Input.attributes(item, %w[field operator value])
      raise ArgumentError unless CONDITION_FIELDS.include?(data['field']) && %w[eq neq].include?(data['operator'])

      if data['field'] == 'origin_channel'
        raise ArgumentError unless data['value'].is_a?(String) && data['value'].strip.length.between?(1, 80)
      else
        JrcServiceDesk::Input.id(data.fetch('value'))
      end
    end
    raise ArgumentError unless %w[defer skip].include?(settings['outside_window'])
    raise ArgumentError unless settings['max_attempts'].is_a?(Integer) && settings['max_attempts'].between?(1, 3)
    raise ArgumentError unless settings['backoff_minutes'].is_a?(Integer) && settings['backoff_minutes'].between?(1, 1440)

    window = JrcServiceDesk::Input.attributes(settings['window'], %w[enabled timezone conditions])
    raise ArgumentError unless [true, false].include?(window['enabled'])

    if window['enabled']
      raise ArgumentError unless window.keys.sort == %w[enabled timezone conditions].sort

      JrcServiceDesk::SnapshotCalendar.new(timezone: window.fetch('timezone'), conditions: window.fetch('conditions'))
    end
    true
  end

  def match?(source)
    return true if settings.empty? || settings.dig('conditions', 'items').empty?

    fields = source.condition_fields
    return false unless fields.is_a?(Hash) && settings['conditions']['items'].all? { |item| fields.key?(item['field']) }

    matches = settings['conditions']['items'].map do |item|
      equal = fields[item['field']].to_s == item['value'].to_s
      item['operator'] == 'eq' ? equal : !equal
    end
    settings['conditions']['operator'] == 'all' ? matches.all? : matches.any?
  end

  def next_time(time = Time.current)
    window = settings['window']
    return time unless window && window['enabled']

    calendar = JrcServiceDesk::SnapshotCalendar.new(timezone: window.fetch('timezone'), conditions: window.fetch('conditions'))
    # One elapsed second inside the allowed calendar; subtracting preserves an
    # already open window and gives its exact next opening otherwise.
    calendar.advance(time, 1) - 1.second
  end

  def recipient_ids(ticket)
    [ticket.requester_id, *settings.fetch('additional_contact_ids', [])].uniq
  end

  def copy_ids(snapshot)
    ids = settings.fetch('internal_copy_member_ids', [])
    assignee = snapshot['assignee_account_user_id'] if settings['copy_assignee']
    (ids + [assignee].compact).map(&:to_i).uniq
  end

  def authorized_copies?(ticket, snapshot)
    ids = copy_ids(snapshot)
    members = ticket.account.account_users.where(id: ids).includes(:user)
    return false unless members.size == ids.size

    members.all? do |member|
      ctx = JrcServiceDesk::OperationalContext.new(account: ticket.account, user: member.user, account_user: member)
      ctx.unit_allowed?(ticket.unit) && JrcServiceDesk::TicketPolicy.new(ctx.to_h, ticket).show?
    end
  end

  def self.contact_allowed?(ticket, contact, context)
    return false unless contact && contact.account_id == ticket.account_id
    return false unless contact.id == ticket.requester_id || (ticket.requester.company_id && contact.company_id == ticket.requester.company_id)

    JrcServiceDesk::NativeExecutionContext.with(context.to_h) { ContactPolicy.new(context.to_h, contact).show? }
  end
end
