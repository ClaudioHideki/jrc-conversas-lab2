module JrcOperations
  class SlaClock
    def initialize(request)
      @request = request
      @policy = request.operations_sla_policy
    end

    def start!
      return @request unless @policy
      now = Time.current
      calendar = JrcOperations::BusinessTime.new(@policy.business_hours)
      @request.assign_attributes(
        sla_started_at: @request.sla_started_at || now,
        first_action_due_at: @request.first_action_due_at || calendar.add_minutes(now, @policy.first_action_minutes),
        stage_due_at: @request.stage_due_at || calendar.add_minutes(now, @policy.stage_minutes),
        sla_due_at: @request.sla_due_at || calendar.add_minutes(now, @policy.total_minutes)
      )
      @request
    end

    def mark_first_action!
      return @request if @request.first_action_at.present?
      @request.update_columns(first_action_at: Time.current, updated_at: Time.current)
      @request
    end

    def status_changed!(from:, to:)
      return unless @policy
      if @policy.pause_status?(to) && @request.sla_paused_at.blank?
        paused_at = Time.current
        @request.update_columns(sla_paused_at: paused_at, updated_at: paused_at)
        audit_clock_event!('operations_sla_paused', from: from, to: to, paused_at: paused_at)
      elsif @request.sla_paused_at.present? && !@policy.pause_status?(to)
        resumed_at = Time.current
        calendar = JrcOperations::BusinessTime.new(@policy.business_hours)
        paused_for = calendar.seconds_between(@request.sla_paused_at, resumed_at).to_i
        shifts = {}
        %i[first_action_due_at stage_due_at sla_due_at].each do |column|
          value = @request.public_send(column)
          remaining = calendar.seconds_between(@request.sla_paused_at, value) if value
          shifts[column] = if value && value > @request.sla_paused_at
                             calendar.add_minutes(resumed_at, remaining / 60.0)
                           elsif value
                             value + (resumed_at - @request.sla_paused_at)
                           end
        end
        @request.update_columns(shifts.merge(sla_paused_at: nil,
                                             sla_paused_seconds: @request.sla_paused_seconds.to_i + paused_for,
                                             updated_at: resumed_at))
        audit_clock_event!('operations_sla_resumed', from: from, to: to, paused_seconds: paused_for, resumed_at: resumed_at)
      end
    end

    def stage_changed!
      return unless @policy&.stage_minutes
      due = JrcOperations::BusinessTime.new(@policy.business_hours).add_minutes(Time.current, @policy.stage_minutes)
      @request.update_columns(stage_due_at: due, updated_at: Time.current)
    end

    def snapshot
      stopped = @request.status.in?(%w[completed canceled rejected])
      now = @request.sla_paused_at || (stopped ? @request.completed_at || @request.updated_at : Time.current)
      due = @request.sla_due_at
      started = @request.sla_started_at
      calendar = JrcOperations::BusinessTime.new(@policy&.business_hours)
      total = @policy&.total_minutes&.*(60)
      elapsed = started ? [calendar.seconds_between(started, now) - @request.sla_paused_seconds.to_i, 0].max : nil
      percent = total && elapsed ? ((elapsed / total) * 100).round(1) : nil
      thresholds = Array(@policy&.alert_thresholds).presence || [50, 75, 90, 100]
      triggered = percent ? thresholds.map(&:to_f).select { |threshold| percent >= threshold } : []
      state = if stopped
                'stopped'
              elsif due && now > due
                'overdue'
              elsif percent && percent >= 90
                'critical'
              elsif percent && percent >= 75
                'attention'
              elsif percent && percent >= 50
                'watch'
              else
                'within'
              end
      {
        state: state,
        percent_elapsed: percent,
        triggered_thresholds: stopped || @request.sla_paused_at ? [] : triggered,
        first_action_due_at: @request.first_action_due_at,
        first_action_at: @request.first_action_at,
        first_action_overdue: !stopped && @request.first_action_at.blank? && @request.first_action_due_at.present? && now > @request.first_action_due_at,
        stage_due_at: @request.stage_due_at,
        stage_overdue: @request.stage_due_at.present? && now > @request.stage_due_at && !@request.status.in?(%w[completed canceled rejected]),
        total_due_at: @request.sla_due_at,
        paused_at: @request.sla_paused_at,
        paused_seconds: @request.sla_paused_seconds.to_i,
        alert_thresholds: thresholds
      }
    end

    private

    def audit_clock_event!(event_type, metadata)
      JrcCrm::AuditEvent.create!(
        account_id: @request.account_id, actor_type: 'System', actor_id: nil,
        event_type: event_type, resource_type: 'JrcCrm::BackofficeRequest', resource_id: @request.id,
        from_value: {}, to_value: {}, metadata: metadata.merge(source: 'jrc_operations_sla')
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Could not audit SLA clock event #{event_type} for BackofficeRequest##{@request.id}: #{e.message}")
    end
  end
end
