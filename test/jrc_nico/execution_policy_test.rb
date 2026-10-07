require 'minitest/autorun'
module JrcNico; end
require_relative '../../app/services/jrc_nico/execution_policy'

class NicoExecutionPolicyTest < Minitest::Test
  Command = Struct.new(:message, :source_notice_id)

  def test_explicit_operator_requests_authorize_only_the_requested_local_creation
    assert JrcNico::ExecutionPolicy.automatic?(Command.new('Crie um lead para este contato', nil), 'create_lead')
    assert JrcNico::ExecutionPolicy.automatic?(Command.new('Por favor, cadastre um contato', nil), 'create_contact')
    assert_equal false, JrcNico::ExecutionPolicy.automatic?(Command.new('Crie um lead', nil), 'create_contact')
    assert JrcNico::ExecutionPolicy.automatic?(Command.new('Pode criar um novo lead para este contato', nil), 'create_lead')
    assert JrcNico::ExecutionPolicy.automatic?(Command.new('Agende uma atividade para este contato', nil), 'create_activity')
    assert_equal false, JrcNico::ExecutionPolicy.automatic?(Command.new('Crie um lead para este contato', nil), 'create_contact')
    assert_equal false, JrcNico::ExecutionPolicy.automatic?(Command.new('Como criar um lead?', nil), 'create_lead')
    assert_equal false, JrcNico::ExecutionPolicy.automatic?(Command.new('Se eu pedir, crie um lead', nil), 'create_lead')
  end

  def test_customer_text_never_authorizes_an_operator_write
    assert_equal false, JrcNico::ExecutionPolicy.automatic?(Command.new('Crie um lead', 10), 'create_lead')
  end

  def test_preview_and_negated_execution_do_not_authorize_writes
    ['Crie um lead, mas não executar', 'Crie um lead como prévia', 'Simule criar um lead', 'Crie um lead, não crie agora'].each do |message|
      assert_equal false, JrcNico::ExecutionPolicy.automatic?(Command.new(message, nil), 'create_lead')
    end
  end

  def test_sending_delegation_and_configuration_require_the_existing_confirmation
    %w[send_message delegate_conversations update_conversation update_contact create_campaign start_sip_call set_reporting_timezone].each do |tool|
      assert_equal false, JrcNico::ExecutionPolicy.automatic?(Command.new('Crie um lead e execute tudo', nil), tool)
    end
  end
end
