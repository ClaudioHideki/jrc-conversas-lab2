require 'logger'

module Llm; end

# SDK diagnostics are untrusted: bodies, URLs and exception messages may contain
# credentials. Discard their contents before forwarding anything to Rails.
# Account-scoped operational diagnostics are logged separately by the services.
class Llm::SafeLogger < Logger
  def initialize(output)
    super(nil)
    @output = output
  end

  def level
    @output.level
  end

  def add(severity, _message = nil, _progname = nil)
    @output.add(severity, '[RubyLLM] detail=[REDACTED]')
  end

  alias log add
end
