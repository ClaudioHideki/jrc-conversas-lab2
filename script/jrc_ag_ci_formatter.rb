# Keep CI console output bounded; the complete native results stay in the JSON artifact.
class JrcAgCiFormatter
  RSpec::Core::Formatters.register self, :example_group_started, :example_failed, :dump_summary

  def initialize(output)
    @output = output
  end

  def example_group_started(notification)
    group = notification.group
    @output.puts "Native source: #{group.metadata[:file_path]}" if group.parent_groups.length == 1
  end

  def example_failed(notification)
    example = notification.example
    exception = example.exception
    @output.puts "FAILED #{example.location}: #{exception.class.name} #{exception.message.lines.first.to_s[0, 500]}"
  end

  def dump_summary(notification)
    @output.puts "Native result: #{notification.example_count} examples, #{notification.failure_count} failures, #{notification.pending_count} pending"
  end
end
