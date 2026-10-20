require 'rails_helper'

RSpec.describe 'NICO asynchronous operator planning', type: :request do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_nico/operations" }
  let(:input) { { request_id: SecureRandom.uuid, message: 'Quantos contatos temos?' } }

  before do
    allow(JrcNico::OperationalInference).to receive(:call)
      .and_return('reply' => 'Consulta concluída.', 'tool' => '', 'arguments' => {})
  end

  it 'returns a persisted pending request without calling the provider in the web request' do
    post "#{base}/ask", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('commands').first.fetch('status')).to eq('planning')
    expect(JrcNico::OperationalInference).not_to have_received(:call)

    command = JrcNico::Command.last
    JrcNico::PlanCommandJob.perform_now(command.id)
    get base, headers: headers
    expect(response.parsed_body.fetch('commands').first.fetch('status')).to eq('succeeded')
    expect(response.parsed_body.fetch('messages').last.fetch('content')).to eq('Consulta concluída.')
  end

  it 'does not duplicate a request or redispatch a completed job' do
    2.times { post "#{base}/ask", params: input, headers: headers, as: :json }
    expect(JrcNico::Command.where(request_id: input[:request_id]).count).to eq(1)
    command = JrcNico::Command.last
    2.times { JrcNico::PlanCommandJob.perform_now(command.id) }
    expect(JrcNico::OperationalInference).to have_received(:call).once
    expect(command.session.reload.messages.count { |message| message['role'] == 'user' }).to eq(1)
  end

  it 'rechecks account access before the worker calls the provider' do
    post "#{base}/ask", params: input, headers: headers, as: :json
    account.update!(custom_attributes: { 'nico_enabled' => false })
    command = JrcNico::Command.last
    JrcNico::PlanCommandJob.perform_now(command.id)
    expect(JrcNico::OperationalInference).not_to have_received(:call)
    expect(command.reload.status).to eq('failed')
  end

  it 'does not retry an interrupted dispatch and preserves unknown reservations' do
    post "#{base}/ask", params: input, headers: headers, as: :json
    command = JrcNico::Command.last
    command.update!(execution_context: command.execution_context.merge('planning_started_at' => 25.minutes.ago.iso8601))
    command.update_column(:updated_at, 25.minutes.ago)
    JrcNico::PlanCommandJob.perform_now(command.id)
    expect(JrcNico::OperationalInference).not_to have_received(:call)
    JrcNico::PlanningRecoveryJob.perform_now
    expect(command.reload.status).to eq('unknown')
    expect(command.reply).to be_present
  end

  it 'rejects a second request while the first queued request is still planning' do
    post "#{base}/ask", params: input, headers: headers, as: :json
    JrcNico::Command.last.update!(created_at: 3.minutes.ago)
    expect do
      post "#{base}/ask", params: input.merge(request_id: SecureRandom.uuid), headers: headers, as: :json
    end.not_to change(JrcNico::Command, :count)
    expect(response).to have_http_status(:too_many_requests)
  end

  it 'recovers a queued request that never started without redispatching a started request' do
    post "#{base}/ask", params: input, headers: headers, as: :json
    command = JrcNico::Command.last
    command.update_column(:updated_at, 3.minutes.ago)
    expect { JrcNico::PlanningRecoveryJob.perform_now }.to have_enqueued_job(JrcNico::PlanCommandJob).with(command.id)
    expect(JrcNico::OperationalInference).not_to have_received(:call)
  end

  it 'discards a delayed answer when inbox access is revoked while the provider is working' do
    member = account.account_users.find_by!(user: user)
    member.update!(role: :agent)
    inbox = create(:inbox, account: account, enable_auto_assignment: false)
    inbox_member = create(:inbox_member, inbox: inbox, user: user)
    conversation = create(:conversation, account: account, inbox: inbox)
    allow(JrcNico::OperationalInference).to receive(:call) do
      inbox_member.destroy!
      { 'reply' => 'PRIVATE ANSWER AFTER REVOCATION', 'tool' => '', 'arguments' => {} }
    end
    post "#{base}/ask", params: input.merge(conversation_id: conversation.display_id), headers: headers, as: :json
    command = JrcNico::Command.last
    JrcNico::PlanCommandJob.perform_now(command.id)
    expect(command.reload.status).to eq('failed')
    expect(command.session.reload.messages.to_json).not_to include('PRIVATE ANSWER AFTER REVOCATION')
  end
end
