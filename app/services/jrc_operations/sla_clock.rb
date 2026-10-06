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
      now = Time.current
      attributes = { first_action_at: now, updated_at: now }
      if @request.respond_to?(:metadata) && @request.sla_started_at
        calendar = JrcOperations::BusinessTime.new(@policy&.business_hours)
        seconds = [calendar.seconds_between(@request.sla_started_at, now) - @request.sla_paused_seconds.to_i, 0].max
        attributes[:metadata] = (@request.metadata || {}).merge('first_action_elapsed_seconds' => seconds)
      end
      @request.update_columns(attributes)
      @request
    end

    def status_changed!(from:, to:)
      return unless @policy
      if @policy.pause_status?(to) && @request.sla_paused_at.blank?
        paused_at = Time.current
        @request.update_columns(sla_paused_at: paused_at, updated_at: paused_at)
        sync_agenda!
        audit_clock_event!('operations_sla_paused', from: from, to: to, paused_at: paused_at)
      elsif @request.sla_paused_at.present? && !@policy.pause_status?(to)
        resumed_at = Time.current
        calendar = JrcOperations::BusinessTime.new(@policy.business_hours)
        paused_for = calendar.seconds_between(@request.sla_paused_at, resumed_at).to_i
        shifts = {}
        deadlines = %i[first_action_due_at stage_due_at sla_due_at]
        deadlines << :due_at if @request.respond_to?(:due_at)
        deadlines.each do |column|
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
        sync_agenda!
        audit_clock_event!('operations_sla_resumed', from: from, to: to, paused_seconds: paused_for, resumed_at: resumed_at)
      end
    end

    def stage_changed!
      return unless @policy&.stage_minutes
      due = JrcOperations::BusinessTime.new(@policy.business_hours).add_minutes(Time.current, @policy.stage_minutes)
      @request.update_columns(stage_due_at: due, updated_at: Time.current)
    end

    def snapshot
      stopped = @request.status.in?(%w[completed canceled rejected dismissed])
      now = @request.sla_paused_at || (stopped ? @request.completed_at || @request.updated_at : Time.current)
      due = @request.sla_due_at
      started = @request.sla_started_at
      calendar = JrcOperations::BusinessTime.new(@policy&.business_hours)
      total = @policy&.total_minutes&.*(60)
      elapsed = started ? [calendar.seconds_between(started, now) - @request.sla_paused_seconds.to_i, 0].max : nil
      percent = total && elapsed ? ((elapsed / total) * 100).round(1) : nil
      thresholds = Array(@policy&.alert_thresholds).presence || [50, 75, 90, 100]
      triggered = percent ? thresholds.map(&:to_f).select { |threshold| percent >= threshold } : []
      total_overdue = !stopped && due.present? && now > due
      first_action_overdue = !stopped && @request.first_action_at.blank? && @request.first_action_due_at.present? && now > @request.first_action_due_at
      stage_overdue = !stopped && @request.stage_due_at.present? && now > @request.stage_due_at
      state = if stopped
                'stopped'
              elsif total_overdue || first_action_overdue || stage_overdue
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
        first_action_overdue: first_action_overdue,
        stage_due_at: @request.stage_due_at,
        stage_overdue: stage_overdue,
        total_overdue: total_overdue,
        total_due_at: @request.sla_due_at,
        paused_at: @request.sla_paused_at,
        paused_seconds: @request.sla_paused_seconds.to_i,
        alert_thresholds: thresholds
      }
    end

    private

    def sync_agenda!
      return unless @request.respond_to?(:activity) && @request.activity && @request.respond_to?(:due_at)

      activity = @request.activity
      metadata = activity.metadata.except('relationship_sla_paused_at')
      metadata['relationship_sla_paused_at'] = @request.sla_paused_at.iso8601 if @request.sla_paused_at
      activity.update!(due_at: @request.due_at, metadata: metadata)
    end

    def audit_clock_event!(event_type, metadata)
      JrcCrm::AuditEvent.create!(
        account_id: @request.account_id, actor_type: 'System', actor_id: nil,
        event_type: event_type, resource_type: @request.class.name, resource_id: @request.id,
        from_value: {}, to_value: {}, metadata: metadata.merge(source: 'jrc_operations_sla')
      )
    end
  end
end
