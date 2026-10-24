# frozen_string_literal: true

# Only reviewed codes and messages may reach the operational response.
class JrcServiceDesk::RequestValidationError < ArgumentError
  MESSAGES = {
    'requester_company_mismatch' => 'Selecione um solicitante vinculado à empresa atendida.',
    'requester_is_company' => 'Selecione uma pessoa como solicitante. O registro escolhido representa uma empresa.'
  }.freeze
  attr_reader :code

  def initialize(code)
    @code = code
    super(MESSAGES.fetch(code))
  end
end
