# Keep CI console output bounded; the complete native results stay in the JSON artifact.
class JrcAgCiFormatter
  RSpec::Core::Formatters.register self, :example_group_started, :example_started, :example_finished, :example_failed, :dump_summary

  def initialize(output)
    @output = output
    @watchdog = Thread.new do
      loop do
        sleep 5
        next unless @current && Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at > 300

        @output.puts "NATIVE EXAMPLE STALLED: #{@current}; this is a failed CI execution, never an approved result"
        Thread.list.each { |thread| @output.puts Array(thread.backtrace).first(15).join("\n") }
        if ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
          begin
            PG.connect(host: ENV.fetch('POSTGRES_HOST'), dbname: ENV.fetch('POSTGRES_DATABASE'),
                       user: ENV.fetch('POSTGRES_USERNAME'), password: ENV.fetch('POSTGRES_PASSWORD'), connect_timeout: 3) do |pg|
              rows = pg.exec("SELECT pid, state, wait_event_type, wait_event, pg_blocking_pids(pid)::text AS blocking_pids, " \
                             "EXTRACT(EPOCH FROM clock_timestamp() - query_start)::integer AS query_age_seconds " \
                             "FROM pg_stat_activity WHERE datname=current_database() ORDER BY pid").to_a
              @output.puts "Synthetic database activity (no SQL text): #{JSON.generate(rows)}"
            end
          rescue StandardError => e
            @output.puts "Synthetic diagnostic unavailable: #{e.class.name}"
          end
          @output.flush
          Process.kill('TERM', Process.pid)
        end
        break
      end
    end
  end

  def example_started(notification)
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @current = notification.example.location
  end

  def example_finished(notification)
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @current = "after #{notification.example.location}"
  end

  def example_group_started(notification)
    group = notification.group
    @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @current = "group #{group.metadata[:file_path]}:#{group.metadata[:line_number]}"
    @output.puts "Native source: #{group.metadata[:file_path]}" if group.parent_groups.length == 1
  end

  def example_failed(notification)
    example = notification.example
    exception = example.exception
    @output.puts "FAILED #{example.location}: #{exception.class.name} #{exception.message.lines.first.to_s[0, 500]}"
  end

  def dump_summary(notification)
    @watchdog.kill
    @output.puts "Native result: #{notification.example_count} examples, #{notification.failure_count} failures, #{notification.pending_count} pending"
  end
end
