class JrcCustomers::ImportIssue < StandardError
  attr_reader :field, :code

  def initialize(message, field:, code: 'VALIDATION_FAILED')
    super(message)
    @field = field
    @code = code
  end
end
