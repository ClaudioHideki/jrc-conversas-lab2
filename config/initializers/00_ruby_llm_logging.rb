require 'ruby_llm'
require Rails.root.join('lib/llm/safe_logger')

# Configure once at boot, before the SDK memoizes its logger. This logger carries
# no account or credential state and remains safe when DEBUG is enabled.
RubyLLM.configure do |config|
  config.logger = Llm::SafeLogger.new(Rails.logger)
end
RubyLLM.logger
