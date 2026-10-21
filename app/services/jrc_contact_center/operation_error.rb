# frozen_string_literal: true

class JrcContactCenter::OperationError < StandardError
  attr_reader :code, :status

  def initialize(code, status: :unprocessable_entity)
    @code = code
    @status = status
    super(code)
  end
end
