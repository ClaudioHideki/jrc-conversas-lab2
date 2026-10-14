class JrcOperator::Error < StandardError
  attr_reader :status

  def initialize(code, status = 422)
    @status = status
    super(code)
  end
end
