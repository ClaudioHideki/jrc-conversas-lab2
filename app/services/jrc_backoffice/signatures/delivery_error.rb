class JrcBackoffice::Signatures::DeliveryError < StandardError
  attr_reader :code

  def initialize(code)
    @code = code
    super(code)
  end
end
