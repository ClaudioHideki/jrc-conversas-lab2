# frozen_string_literal: true

# Adapts the versioned wizard configuration to the EXISTING dispatch engine.
# Chooses one authorized channel before enrollment; it never broadcasts or retries
# an unknown provider result on another channel.
class JrcRelationship::SurveyModelRuntime
  def self.configuration(rule)
    rule.effective_settings['service_desk_model']
  end

  def self.matches?(rule, source, event)
    config = configuration(rule)
    return event == 'closure' unless config
    return false unless source.is_a?(JrcServiceDesk::Ticket) && config['unit_id'].to_s == source.unit_id.to_s

    settings = config.fetch('rules')
    trigger = settings['event']
    matches = case trigger
              when 'closed' then event == 'closure' && source.status.phase == 'closed'
              when 'first_agent_response' then event == 'first_agent_response'
              when 'manual' then event == 'manual'
              else false
              end
    matches && %w[ticket_type_id queue_id priority_id].all? do |key|
      settings[key].blank? || settings[key].to_s == source.public_send(key).to_s
    end
  end

  def self.channel(rule, origin)
    config = configuration(rule)
    return nil unless config
    config.dig('rules', 'channel_order').each do |key|
      row = config.dig('channels', key)
      next unless row && row['enabled'] == true
      return { 'channel' => 'public_link', 'delivery_inbox_id' => nil, 'whatsapp_template' => nil } if key == 'public_link'
      next if key == 'email' && origin.contact&.email.blank?
      conversation = origin.conversation(key, inbox_id: row['inbox_id'])
      next unless conversation
      next unless conversation.can_reply? || (key == 'whatsapp' && row['whatsapp_template'].present?)
      return { 'channel' => key, 'delivery_inbox_id' => row['inbox_id'],
               'whatsapp_template' => row['whatsapp_template'], 'model_message' => row['message'] }
    end
    nil
  end

  def self.scheduled_at(rule, now = Time.current)
    value = now + rule.effective_settings['delay_minutes'].minutes
    next_window(value, configuration(rule)&.dig('rules', 'send_window'))
  end

  def self.next_window(time, window)
    return time unless window && window['enabled'] == true
    zone = ActiveSupport::TimeZone[window.fetch('timezone')]
    raise ArgumentError, 'Invalid survey timezone' unless zone
    local = time.in_time_zone(zone)
    start_h, start_m = window.fetch('start').split(':').map(&:to_i)
    end_h, end_m = window.fetch('end').split(':').map(&:to_i)
    0.upto(7) do |offset|
      day = local.to_date + offset
      next unless window.fetch('days').include?(day.wday)
      first = zone.local(day.year, day.month, day.day, start_h, start_m)
      last = zone.local(day.year, day.month, day.day, end_h, end_m)
      candidate = [time, first].max
      return candidate if candidate < last
    end
    raise ArgumentError, 'No available survey sending window'
  end

  def self.source_ready?(survey, source)
    config = survey.rule_snapshot.dig('settings', 'service_desk_model')
    return source.completed? unless config
    return false unless source.source.is_a?(JrcServiceDesk::Ticket)
    # A response event or explicit authorized manual enrollment can happen before closure.
    case config.dig('rules', 'event')
    when 'first_agent_response' then survey.metadata['survey_trigger'] == 'first_agent_response'
    when 'manual' then survey.metadata['survey_trigger'] == 'manual'
    else source.source.status.phase == 'closed'
    end
  end
end
