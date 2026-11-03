class JrcMigrations::Error < StandardError
  attr_reader :private_context

  def initialize(message, private_context: {})
    super(message)
    @private_context = private_context
  end
end
