class Pabx::Error < StandardError
  attr_reader :code

  def initialize(code)
    @code = code.to_s
    super(@code)
  end
end
