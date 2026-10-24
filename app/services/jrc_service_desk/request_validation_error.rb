# frozen_string_literal: true

# Only reviewed codes and messages may reach the operational response.
class JrcServiceDesk::RequestValidationError < ArgumentError
  MESSAGES = {
    'requester_company_mismatch' => 'Selecione um solicitante vinculado à empresa atendida.',
    'requester_is_company' => 'Selecione uma pessoa como solicitante. O registro escolhido representa uma empresa.',
    'requester_review_required' => 'O cadastro importado ou técnico precisa de revisão antes de ser utilizado como pessoa solicitante.'
  }.freeze
  attr_reader :code

  def initialize(code)
    @code = code
    super(MESSAGES.fetch(code))
  end
end
