class Pabx::Sync
  MAX_PAGES = 20
  MAX_SECONDS = 60

  def initialize(integration)
    @integration = integration
  end

  def call
    failure = nil
    result = @integration.with_lock(requires_new: true) do
      settings = Pabx::Settings.new(@integration)
      next unless settings.sync_enabled?

      begin
        @integration.class.transaction(requires_new: true) do
          now = Time.current
          start = window_start(settings, now)
          finish = [now, start + settings.value('window_days', 7).days].min
          provider = Pabx::Provider.new(@integration)
          provider.verify_scope!
          count = import_pages(provider, settings, start, finish)
          completed = Time.current.iso8601
          @integration.update!(pabx_sync_state: @integration.pabx_sync_state.merge(
            'cursor' => finish.iso8601, 'last_success_at' => completed, 'last_attempt_at' => completed,
            'last_error' => nil, 'queued_at' => nil, 'imported' => count
          ))
          count
        end
      rescue Pabx::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
        failure = error.is_a?(Pabx::Error) ? error : Pabx::Error.new('PERSISTENCE_FAILED')
        @integration.reload.update!(pabx_sync_state: @integration.pabx_sync_state.merge('last_error' => failure.code,
                                  'last_attempt_at' => Time.current.iso8601, 'queued_at' => nil))
        nil
      end
    end
    raise failure, cause: nil if failure

    result
  end

  private

  def window_start(settings, finish)
    cursor = @integration.pabx_sync_state['cursor']
    floor = finish - settings.value('window_days', 7).days
    return floor if cursor.nil?
    raise Pabx::Error, 'INVALID_CURSOR' unless cursor.is_a?(String)
    value = Time.iso8601(cursor)
    raise Pabx::Error, 'INVALID_CURSOR' if value > finish

    value - settings.value('overlap_seconds', 120).seconds
  rescue ArgumentError
    raise Pabx::Error, 'INVALID_CURSOR', cause: nil
  end

  def import_pages(provider, settings, start, finish)
    count = 0
    seen = Set.new
    expected_total = nil
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MAX_SECONDS
    MAX_PAGES.times do |index|
      raise Pabx::Error, 'TIME_LIMIT_EXCEEDED' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      result = provider.call_history(from: start, to: finish, page: index + 1)
      raise Pabx::Error, 'TIME_LIMIT_EXCEEDED' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      expected_total ||= result[:total]
      raise Pabx::Error, 'INVALID_PAGINATION' unless expected_total == result[:total]
      if result[:current_page] && result[:current_page] != index + 1
        raise Pabx::Error, 'INVALID_PAGINATION'
      end
      rows = result.fetch(:rows)
      raise Pabx::Error, 'INVALID_PAGINATION' if rows.empty? && count < result[:total]
      raise Pabx::Error, 'INVALID_PAGINATION' if count + rows.size > result[:total]
      raise Pabx::Error, 'INVALID_PAGINATION' if rows.size > settings.value('cdr_page_size', 20)

      rows.each do |row|
        raise Pabx::Error, 'TIME_LIMIT_EXCEEDED' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise Pabx::Error, 'REPEATED_PAGE' unless seen.add?(row.fetch(:external_unique_id))

        persist(settings, row)
      end
      count += rows.size
      return count if count == result[:total]
    end
    raise Pabx::Error, 'PAGE_LIMIT_EXCEEDED'
  end

  def persist(settings, row)
    record = TelephonyCallRecord.find_or_initialize_by(account_id: @integration.account_id, provider: Pabx::Settings::PROVIDER,
                                                      external_tenant: settings.data.fetch('expected_tenant').to_s,
                                                      external_unique_id: row.fetch(:external_unique_id))
    record.assign_attributes(row.merge(synced_at: Time.current))
    record.save!
  end
end
